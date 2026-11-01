"""Convert the demo's extracted constants (demo.json) into the wordbase fixture for #10640.

Usage: node demo/fixture/extract_demo.js demo/index.html > demo.json
       uv run --with pyyaml demo/fixture/build.py demo.json prompts/fixture-rewrites.json wordbase
"""

import ast
import json
import os
import re
import subprocess
import sys

import yaml

REPO = "/Users/k3sc0re/openathena/marin-viewer/marin"
BASE = "8a92f90382559206b03ead1afbbd32c35f68fcff"
HEAD = "01a8bb8f0bea2dde1de90274ed695c25147b9f06"
PREPARED = "2026-10-30T00:00:00Z"
NOTED = "2026-11-01"
SESSION = "demo-10640"
BY = "hand-written demo fixture"

demo = json.load(open(sys.argv[1]))
REWRITES = json.load(open(sys.argv[2]))
OUT = sys.argv[3]
SRC = demo["SRC"]
report = []


# ---- Lint-driven rewrites decided by the coordinator (prompts/fixture-rewrites.json)
def walk(obj, seg):
    if isinstance(obj, dict):
        return obj[seg]
    for item in obj:
        if isinstance(item, dict) and str(item.get("id")) == seg:
            return item
    return obj[int(seg)]


for r in REWRITES:
    *parents, field = r["path"]
    holder = demo
    for seg in parents:
        holder = walk(holder, seg)
    assert holder[field].count(r["from"]) == 1, r
    holder[field] = holder[field].replace(r["from"], r["to"])


def git(*args):
    return subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True, check=True).stdout


_decls = {}


def decls(path):
    """Declarations Radiology's Python symbol query reports: defs, classes, module-level assignments.

    `start` includes decorators; `def` is the line of the declaration itself.
    """
    if path in _decls:
        return _decls[path]
    src = git("show", f"{HEAD}:{path}")
    out = []

    def visit(node, parents):
        for ch in ast.iter_child_nodes(node):
            if isinstance(ch, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                start = min([ch.lineno] + [x.lineno for x in ch.decorator_list])
                out.append({"q": ".".join(parents + [ch.name]), "name": ch.name, "start": start, "def": ch.lineno, "end": ch.end_lineno, "parents": parents})
                visit(ch, parents + [ch.name])
            elif not parents and isinstance(ch, (ast.Assign, ast.AnnAssign)):
                targets = ch.targets if isinstance(ch, ast.Assign) else [ch.target]
                if len(targets) == 1 and isinstance(targets[0], ast.Name):
                    out.append({"q": targets[0].id, "name": targets[0].id, "start": ch.lineno, "def": ch.lineno, "end": ch.end_lineno, "parents": []})
            else:
                visit(ch, parents)

    visit(ast.parse(src), [])
    _decls[path] = (out, src.splitlines())
    return _decls[path]


def trim(lines, a, b):
    while a < b and not lines[a - 1].strip():
        a += 1
    while b > a and not lines[b - 1].strip():
        b -= 1
    return a, b


def functions_for(path, a0, b0, where):
    """Every consecutive declaration the excerpt spans, or [] for a whole-module excerpt."""
    ds, lines = decls(path)
    a, b = trim(lines, a0, b0)
    first, last = trim(lines, 1, len(lines))
    if a0 == 1 and b >= last:
        return []
    cover = sorted((d for d in ds if d["start"] <= a and d["end"] >= b), key=lambda d: d["end"] - d["start"])
    inner = cover[0] if cover else None
    scope = inner["q"].split(".") if inner else []
    children = [d for d in ds if d["parents"] == scope and d["start"] <= b and d["end"] >= a]
    picked = [inner] if inner and (a in (inner["start"], inner["def"]) or not children) else children
    span = (picked[0]["start"], picked[-1]["end"])
    if not (a in (picked[0]["start"], picked[0]["def"]) and b == span[1]):
        report.append(f"{where}: {path.removeprefix(SRC)} lines {a0}-{b0}, declarations {[d['q'] for d in picked]} span {span[0]}-{span[1]}")
    return [d["q"] for d in picked]


def resolve_name(path, name):
    ds, _ = decls(path)
    hits = [d for d in ds if name in {d["name"], d["q"]} | {".".join(d["q"].split(".")[i:]) for i in range(len(d["q"].split(".")))}]
    return hits[0] if len(hits) == 1 else None


def anchor(path, line, label, where):
    """The declaration a box stands for: its label when the label is a declaration, else the narrowest one at the line."""
    ds, _ = decls(path)
    narrow = sorted((d for d in ds if d["start"] <= line <= d["end"]), key=lambda d: d["end"] - d["start"])[0]
    named = resolve_name(path, label) if re.fullmatch(r"[A-Za-z_][\w.]*", label) else None
    if named and named["q"] != narrow["q"]:
        report.append(f"{where}: label `{label}` is the declaration {named['q']} at line {named['def']}; the demo's line {line} is inside {narrow['q']}")
    return (named or narrow)["q"]


def layers(obj, l1key="l1"):
    out = {"l1": obj[l1key]}
    if obj.get("l2"):
        out["l2"] = obj["l2"]
    if obj.get("l3"):
        out["l3"] = obj["l3"]
    return out


def front(meta, body=""):
    text = yaml.safe_dump(meta, sort_keys=False, allow_unicode=True, width=10**9)
    return f"---\n{text}---\n" + (f"\n{body}" if body else "")


def write(rel, content):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content)
    print("wrote", rel)


def note_line(text):
    return f"- {NOTED} · {HEAD[:7]} · session {SESSION} · {text}\n"


# Memory notes, keyed by the entry their target names.
memory = {}
for m in demo["MEMORY"]:
    target, section = [s.strip() for s in m["target"].split("·")]
    memory.setdefault(target.removeprefix("wordbase/"), []).append((section, m["text"]))

# ---- PR description
write(
    "prs/10640/pr.md",
    front(
        {
            "kind": "pr",
            "number": 10640,
            "repo": "marin-community/marin",
            "title": "Add persistent container tasks and host capabilities",
            "author": "rjpower",
            "state": "MERGED",
            "head": HEAD,
            "base": BASE,
            "merge_base": git("merge-base", BASE, HEAD).strip(),
            "prepared_at": PREPARED,
            "session_id": SESSION,
            "commit": HEAD,
            "updated": PREPARED,
            "by": BY,
            **layers(demo["PR"]),
        }
    ),
)

# ---- Code path
steps = []
for s in demo["STEPS"]:
    excerpts = []
    for f, a, b in s["ex"]:
        path = SRC + f
        excerpts.append({"path": path, "functions": functions_for(path, a, b, f"step {s['id']}"), "lines": [a, b]})
    step = {"id": s["id"], "title": s["title"], "l1": s["s"]}
    if s.get("l2"):
        step["l2"] = s["l2"]
    step["node"] = s["node"]
    step["excerpts"] = excerpts
    steps.append(step)
write("prs/10640/code-path.json", json.dumps(steps, indent=2, ensure_ascii=False) + "\n")


# ---- Diagrams: grid cells placed by hand from the demo's boxes, at most 4 columns by 3 rows.
# Each cell is (col, row) or (col, row, span). arrangement() checks them against the demo's coordinates.
MAX_COLS, MAX_ROWS = 4, 3
GRIDS = {
    "pr diagram": {
        "driver": (0, 0), "relay": (1, 0), "spec": (2, 0),
        "limits": (0, 1), "session": (1, 1), "teardown": (2, 1),
        "pipes": (0, 2), "daytona": (1, 2), "group": (2, 2), "runtime": (3, 2),
    },
    "step diagram 2": {
        "ct": (0, 0), "cp": (1, 0), "cm": (2, 0), "mo": (3, 0),
        "sk": (1, 1), "cf": (3, 1),
        "ex": (0, 2), "tc": (2, 2),
    },
    "step diagram 4": {
        "pm": (0, 0), "st": (3, 0),
        "lo": (0, 1), "do": (1, 1), "da": (2, 1), "bb": (3, 1),
        "ss": (1, 2), "ds": (2, 2),
    },
    "step diagram 6": {
        "cl": (0, 0), "sl": (1, 0), "rs": (2, 0), "hd": (3, 0),
        "hr": (0, 1), "pu": (2, 1),
        "em": (0, 2), "rr": (1, 2), "wr": (3, 2),
    },
    "step diagram 7": {
        "ca": (0, 0), "oc": (1, 0), "tc": (2, 0),
        "ac": (1, 1), "fo": (2, 1),
        "re": (0, 2),
    },
    # 11 boxes cannot keep every relation in 4 x 3: the demo puts five backends in its bottom row.
    # The Iris sandbox box moves up beside Shellbox, next to the Iris box it feeds.
    "system diagram": {
        "taskforge": (0, 0), "rollout": (1, 0), "compendium": (2, 0),
        "harbor": (0, 1), "shellbox": (1, 1), "b-iris": (2, 1), "iris": (3, 1),
        "b-local": (0, 2), "b-docker": (1, 2), "b-daytona": (2, 2), "b-qemu": (3, 2),
    },
}


def arrangement(nodes, cells, where):
    """Report demo relations the grid breaks: A left of B when their boxes share rows of pixels, A above B
    when they share columns of pixels."""
    for a in nodes:
        for b in nodes:
            ca, cb = cells[a["id"]], cells[b["id"]]
            share_y = a["y"] < b["y"] + b["h"] and b["y"] < a["y"] + a["h"]
            share_x = a["x"] < b["x"] + b["w"] and b["x"] < a["x"] + a["w"]
            if share_y and a["x"] + a["w"] <= b["x"] and not ca["col"] + ca.get("span", 1) <= cb["col"]:
                report.append(f"{where}: {a['id']} is left of {b['id']} in the demo, not in the grid")
            if share_x and a["y"] + a["h"] <= b["y"] and not ca["row"] < cb["row"]:
                report.append(f"{where}: {a['id']} is above {b['id']} in the demo, not in the grid")


def grid_cells(nodes, where):
    table = GRIDS[where]
    assert set(table) == {n["id"] for n in nodes}, (where, set(table) ^ {n["id"] for n in nodes})
    cells = {nid: {"col": c[0], "row": c[1], **({"span": c[2]} if len(c) > 2 else {})} for nid, c in table.items()}
    taken = {}
    for nid, c in cells.items():
        assert c["row"] < MAX_ROWS and c["col"] + c.get("span", 1) <= MAX_COLS, (where, nid)
        for col in range(c["col"], c["col"] + c.get("span", 1)):
            assert (c["row"], col) not in taken, f"{where}: {nid} overlaps {taken[(c['row'], col)]}"
            taken[(c["row"], col)] = nid
    arrangement(nodes, cells, where)
    return cells


def inside(n, g):
    return n["x"] >= g["x"] and n["y"] >= g["y"] and n["x"] + n["w"] <= g["x"] + g["w"] and n["y"] + n["h"] <= g["y"] + g["h"]


def diagram(d, where, rename=None, extra=None):
    rename = rename or {}
    cells = grid_cells(d["nodes"], where)
    nodes = []
    for n in d["nodes"]:
        node = {"id": rename.get(n["id"], n["id"]), "label": n["label"], "sub": n["sub"]}
        if "step" in n:
            node["step"] = n["step"]
        if "at" in n:
            path = SRC + n["at"][0]
            node["at"] = {"path": path, "function": anchor(path, n["at"][1], n["label"], f"{where} box {n['id']}")}
        node.update((extra or {}).get(n["id"], {}))
        node["grid"] = cells[n["id"]]
        nodes.append(node)
    edges = [[rename.get(e[0], e[0]), rename.get(e[1], e[1]), *e[2:]] for e in d["edges"]]
    out = {"layout": {"mode": "grid"}, "nodes": nodes, "edges": edges}
    groups = [{"label": g["label"], "members": [rename.get(n["id"], n["id"]) for n in d["nodes"] if inside(n, g)]} for g in d.get("groups", [])]
    if groups:
        out["groups"] = groups
    return out


by_id = {s["id"]: s for s in demo["STEPS"]}
step_dia = {}
for k, d in demo["STEP_DIA"].items():
    assert d["title"] == by_id[int(k)]["title"], (k, d["title"])
    step_dia[k] = diagram(d, f"step diagram {k}")
write(
    "prs/10640/diagrams.json",
    json.dumps({"pr": diagram(demo["SUB"], "pr diagram"), "steps": step_dia}, indent=2, ensure_ascii=False) + "\n",
)

# ---- Review notes
rows = []
for f in demo["FINDINGS"]:
    rows.append(
        {
            "id": f["id"],
            "path": SRC + f["path"],
            "line": f["line"],
            "side": "head",
            "commit": HEAD,
            "severity": f["sev"],
            "status": f["status"],
            "who": f["who"],
            "l1": f["l1"],
            "l2": f["l2"],
            "created": PREPARED,
            "updated": PREPARED,
        }
    )
write("prs/10640/notes.jsonl", "".join(json.dumps(n, ensure_ascii=False) + "\n" for n in rows))

# ---- Per-file change descriptions (file-header text)
write("prs/10640/files.json", json.dumps({SRC + f: layers(v) for f, v in demo["FILES"].items()}, indent=2, ensure_ascii=False) + "\n")

# ---- File entries
for f, v in demo["FILES"].items():
    rel = SRC + f + ".md"
    notes = memory.pop(rel, [])
    body = "## Notes\n\n" + "".join(note_line(t) for _, t in notes) if notes else ""
    meta = {"kind": "file", "path": SRC + f, "commit": HEAD, "updated": PREPARED, "by": BY, **layers(v), "system": "shellbox"}
    write(rel, front(meta, body))

# ---- System entry, from CTX
rename = {"rollout": "rolloutengine", "compendium": "taskcompendium"}
paths = {
    "taskforge": ["lib/taskforge/"],
    "rollout": ["lib/rolloutengine/"],
    "compendium": ["lib/taskcompendium/"],
    "harbor": ["vendor/harbor/"],
    "shellbox": ["lib/shellbox/"],
    "iris": ["lib/iris/"],
    "b-local": [SRC + "backends/local/"],
    "b-docker": [SRC + "backends/docker/", SRC + "backends/gvisor/"],
    "b-daytona": [SRC + "backends/daytona/"],
    "b-iris": [SRC + "backends/iris/"],
    "b-qemu": [SRC + "backends/qemu/", SRC + "backends/shellsim/"],
}
ctx = diagram(demo["CTX"], "system diagram", rename, {k: {"paths": v} for k, v in paths.items()})
notes = memory.pop("systems/shellbox.md", [])
write(
    "systems/shellbox.md",
    front(
        {
            "kind": "system",
            "name": "shellbox",
            "commit": HEAD,
            "updated": "2026-11-01T00:00:00Z",
            "by": "claude-opus-5-5 fixture (layers from lib/shellbox/README.md); demo CTX (diagram)",
            "l1": (
                "Shellbox runs commands in sandboxed machines behind a machine API with seven backends, groups "
                "machines into multi-container tasks, and relays HTTP requests from a sandbox to a handler on the host."
            ),
            "l2": (
                "A caller passes a `MachineSpec` to a backend factory's `create` and gets a machine with a persistent "
                "writable filesystem, where `run`, `upload`, `download` and `close` work the same way on QEMU, "
                "ShellSim, Docker, gVisor, Daytona, Iris and the local host. QEMU and ShellSim also back Harbor "
                "environments, and `shellbox.agent:BashAgent` drives their persistent shell from the Harbor process. "
                "`TaskSpec` lists named containers with endpoints and readiness probes; "
                "`LocalMachineFactory.create_task` starts them in bubblewrap on a private loopback network, and the "
                "single-machine `create` builds a one-container task through the same call. Local, Docker, gVisor "
                "and Daytona machines open persistent process sessions through `ProcessMachine.open_process`, and "
                "`serve_http` runs a standard-library listener over such a session so that model credentials stay "
                "with the host handler. QEMU, ShellSim and Iris offer commands and file transfer only."
            ),
            "members": ["lib/shellbox/"],
            "uses": ["iris"],
            "used_by": ["taskforge", "rolloutengine", "taskcompendium", "harbor"],
            "diagram": ctx,
        },
        "## Notes\n\n" + "".join(note_line(t) for _, t in notes),
    ),
)

# ---- Reviewer entry
notes = memory.pop("reviewer.md", [])
write("reviewer.md", front({"kind": "reviewer", "updated": PREPARED, "by": BY}, "## Notes\n\n" + "".join(note_line(t) for _, t in notes)))
assert not memory, memory

print("\nREPORT:")
print("\n".join(report) or "none")
