"""Check wordbase entries and PR outputs against DESIGN.md section 6.

Run from anywhere:

    uv run --with pyyaml prompts/check_fixture.py [--wordbase DIR] [--marin DIR] [--strict]

The script reads every entry under the wordbase and checks required keys and enumerations. Against the
source at the PR's head commit it resolves each excerpt's `functions` with Radiology's matching rule,
checks that they are consecutive declarations under one parent, and resolves each diagram box's `at`.
It checks that every code-path step points at a box in the PR diagram, that grid layouts give every
box a free cell within 4 columns and 3 rows, and that box `paths` exist. It exits 1 when any check fails.

An excerpt whose `lines` differ from the union of its declarations prints a MISMATCH line. The viewer
rewrites `lines` from the declarations, so a mismatch fails only under `--strict`.
"""

import argparse
import ast
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import yaml

VIEWER = Path(__file__).resolve().parent.parent
SEVERITIES = {"high", "medium", "low", "design"}
STATUSES = {"draft", "approved", "rejected", "posted", "resolved"}
SIDES = {"head", "base"}
KINDS = {"file", "system", "pr", "reviewer"}
LAYOUT_MODES = {"auto", "grid"}
DIRECTIONS = {"RIGHT", "DOWN"}
MAX_BOXES = 10
MAX_COLS, MAX_ROWS = 4, 3
NOTE_LINE = re.compile(r"^- \d{4}-\d{2}-\d{2} · [0-9a-f]{7,40} · session \S+ · \S")
SENTENCE_BREAK = re.compile(r"(?<!\be\.g)(?<!\bi\.e)[.!?]\s+[A-Z`]")

errors: list[str] = []
warnings: list[str] = []
mismatches: list[str] = []
counts: dict[str, int] = {}


def fail(where: str, message: str) -> None:
    errors.append(f"{where}: {message}")


def tally(what: str, n: int = 1) -> None:
    counts[what] = counts.get(what, 0) + n


@dataclass(frozen=True)
class Decl:
    """A declaration: enclosing names plus its own, first line (decorators included), its own line, last line."""

    chain: list[str]
    first: int
    line: int
    last: int

    @property
    def name(self) -> str:
        return ".".join(self.chain)


class Repo:
    def __init__(self, root: Path):
        self.root = root
        self._files: dict[tuple[str, str], str | None] = {}
        self._symbols: dict[tuple[str, str], list[Decl]] = {}

    def git(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(["git", "-C", str(self.root), *args], capture_output=True, text=True)

    def has_commit(self, sha: str) -> bool:
        return self.git("cat-file", "-e", f"{sha}^{{commit}}").returncode == 0

    def show(self, commit: str, path: str) -> str | None:
        key = (commit, path)
        if key not in self._files:
            out = self.git("show", f"{commit}:{path}")
            self._files[key] = out.stdout if out.returncode == 0 else None
        return self._files[key]

    def changed(self, base: str, head: str) -> set[str]:
        out = self.git("diff", "--name-only", base, head)
        if out.returncode != 0:
            raise SystemExit(f"git diff {base}..{head} failed: {out.stderr.strip()}")
        return set(out.stdout.split())

    def symbols(self, commit: str, path: str) -> list[Decl]:
        """Declarations in source order.

        Mirrors Radiology's Python symbol query: every function and class definition, plus assignments
        to a bare name at module level.
        """
        key = (commit, path)
        if key in self._symbols:
            return self._symbols[key]
        out: list[Decl] = []

        def walk(node: ast.AST, parents: list[str]) -> None:
            for child in ast.iter_child_nodes(node):
                if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                    first = min([child.lineno] + [d.lineno for d in child.decorator_list])
                    out.append(Decl(parents + [child.name], first, child.lineno, child.end_lineno or child.lineno))
                    walk(child, parents + [child.name])
                elif not parents and isinstance(child, (ast.Assign, ast.AnnAssign)):
                    targets = child.targets if isinstance(child, ast.Assign) else [child.target]
                    if len(targets) == 1 and isinstance(targets[0], ast.Name):
                        out.append(Decl([targets[0].id], child.lineno, child.lineno, child.end_lineno or child.lineno))
                else:
                    walk(child, parents)

        source = self.show(commit, path)
        if source is not None:
            walk(ast.parse(source), [])
        self._symbols[key] = out
        return out

    def resolve(self, commit: str, path: str, name: str) -> "Decl | str":
        """Return the declaration, or an error message.

        A selector matches a declaration when it equals the bare name or any suffix chain of enclosing
        declarations joined with `.` or `::` (Radiology's CodePathSymbolResolver). More than one match
        is an error, as it is in Radiology.
        """
        if not path.endswith(".py"):
            return f"cannot resolve `{name}` in {path}: only Python files are checked"
        if self.show(commit, path) is None:
            return f"{path} does not exist at {commit[:10]}"
        selector = "".join(name.split())
        matches = []
        for decl in self.symbols(commit, path):
            chain = decl.chain
            forms = {chain[-1]}
            for i in range(len(chain) - 1):
                forms.add(".".join(chain[i:]))
                forms.add("::".join(chain[i:]))
            if selector in forms:
                matches.append(decl)
        if not matches:
            return f"`{name}` is not a declaration in {path} at {commit[:10]}"
        if len(matches) > 1:
            return f"`{name}` is ambiguous in {path} at {commit[:10]} ({len(matches)} declarations)"
        return matches[0]

    def siblings(self, commit: str, path: str, decl: "Decl") -> list["Decl"]:
        return [d for d in self.symbols(commit, path) if d.chain[:-1] == decl.chain[:-1]]

    def exists(self, commit: str, path: str) -> bool:
        return self.git("cat-file", "-e", f"{commit}:{path.rstrip('/')}").returncode == 0


def front_matter(path: Path) -> tuple[dict, str] | None:
    text = path.read_text()
    if not text.startswith("---\n"):
        fail(str(path), "no front matter")
        return None
    end = text.find("\n---\n", 4)
    if end < 0:
        fail(str(path), "front matter is not closed")
        return None
    try:
        meta = yaml.safe_load(text[4:end])
    except yaml.YAMLError as error:
        fail(str(path), f"front matter is not YAML: {error}")
        return None
    if not isinstance(meta, dict):
        fail(str(path), "front matter is not a mapping")
        return None
    return meta, text[end + 5 :]


def require(where: str, obj: dict, keys: list[str]) -> bool:
    missing = [k for k in keys if obj.get(k) in (None, "", [])]
    if missing:
        fail(where, f"missing {', '.join(missing)}")
    return not missing


def check_layers(where: str, obj: dict) -> None:
    l1 = obj.get("l1")
    if not isinstance(l1, str) or not l1.strip():
        fail(where, "l1 must be a non-empty string")
    elif SENTENCE_BREAK.search(l1):
        fail(where, "l1 must be a single sentence")
    if "l2" in obj and not isinstance(obj["l2"], str):
        fail(where, "l2 must be a string")
    if "l3" in obj and not (isinstance(obj["l3"], list) and all(isinstance(p, str) and p for p in obj["l3"])):
        fail(where, "l3 must be a list of paragraphs")


def check_notes_section(where: str, body: str, heading: str = "## Notes") -> None:
    lines = body.splitlines()
    if heading not in lines:
        return
    for line in lines[lines.index(heading) + 1 :]:
        if line.startswith("## "):
            break
        if line.strip():
            tally("wordbase notes")
            if not NOTE_LINE.match(line):
                fail(where, f"note line does not match `- date · sha · session id · text`: {line[:60]}")


def check_diagram(where: str, d: object, repo: Repo, commit: str, step_ids: set[int] | None = None) -> set[str]:
    if not isinstance(d, dict) or not isinstance(d.get("nodes"), list) or not d["nodes"]:
        fail(where, "diagram needs a non-empty nodes list")
        return set()
    ids: set[str] = set()
    layout = d.get("layout", {"mode": "auto"})
    if not isinstance(layout, dict) or layout.get("mode") not in LAYOUT_MODES or set(layout) - {"mode", "direction"}:
        fail(where, f"layout {layout} must be {{mode: auto|grid, direction?}}")
        layout = {"mode": "auto"}
    if "direction" in layout and layout["direction"] not in DIRECTIONS:
        fail(where, f"layout direction {layout['direction']} is not one of {sorted(DIRECTIONS)}")
    if len(d["nodes"]) > MAX_BOXES:
        warnings.append(f"{where}: {len(d['nodes'])} boxes, more than the {MAX_BOXES} the preparation prompt allows")
    cells: dict[tuple[int, int], str] = {}
    for n in d["nodes"]:
        nw = f"{where} node {n.get('id')}"
        require(nw, n, ["id", "label"])
        if "sub" not in n:
            fail(nw, "missing sub")
        if n.get("id") in ids:
            fail(nw, "duplicate node id")
        ids.add(n.get("id"))
        if any(k in n for k in ("x", "y", "w", "h")):
            fail(nw, "diagrams carry no pixel coordinates")
        if "step" in n and step_ids is not None and n["step"] not in step_ids:
            fail(nw, f"step {n['step']} is not in code-path.json")
        grid = n.get("grid")
        if grid is not None:
            ok = (
                isinstance(grid, dict)
                and not set(grid) - {"col", "row", "span"}
                and all(isinstance(grid.get(k), int) and grid[k] >= 0 for k in ("col", "row"))
                and isinstance(grid.get("span", 1), int)
                and grid.get("span", 1) >= 1
            )
            if not ok:
                fail(nw, f"grid {grid} must be {{col, row, span?}} with non-negative integers")
            else:
                for col in range(grid["col"], grid["col"] + grid.get("span", 1)):
                    if (grid["row"], col) in cells:
                        fail(nw, f"grid cell row {grid['row']} col {col} is taken by {cells[(grid['row'], col)]}")
                    cells[(grid["row"], col)] = n["id"]
        elif layout["mode"] == "grid":
            fail(nw, "grid layout needs a grid cell on every node")
        paths = n.get("paths")
        if paths is not None:
            if not isinstance(paths, list) or not paths or not all(isinstance(x, str) and x for x in paths):
                fail(nw, "paths must be a non-empty list of repository paths")
            else:
                for x in paths:
                    tally("box paths")
                    if not repo.exists(commit, x):
                        fail(nw, f"path {x} does not exist at {commit[:10]}")
        if "at" in n:
            at = n["at"]
            if not isinstance(at, dict) or not require(nw + " at", at, ["path", "function"]):
                continue
            tally("diagram anchors")
            got = repo.resolve(commit, at["path"], at["function"])
            if isinstance(got, str):
                fail(nw, got)
    if cells:
        cols = max(c for _, c in cells) + 1
        rows = max(r for r, _ in cells) + 1
        if cols > MAX_COLS or rows > MAX_ROWS:
            fail(where, f"grid is {cols} columns by {rows} rows; the card allows {MAX_COLS} by {MAX_ROWS}")
    for e in d.get("edges", []):
        if not isinstance(e, list) or len(e) not in (2, 3) or not all(isinstance(x, str) for x in e):
            fail(where, f"edge {e} must be [from, to, label?]")
        elif e[0] not in ids or e[1] not in ids:
            fail(where, f"edge {e} names a node that does not exist")
    for g in d.get("groups", []):
        require(f"{where} group", g, ["label", "members"])
        for m in g.get("members", []):
            if m not in ids:
                fail(f"{where} group {g.get('label')}", f"member {m} is not a node")
    tally("diagrams")
    return ids


def check_excerpt(where: str, ex: dict, repo: Repo, head: str) -> None:
    """`functions` lists consecutive sibling declarations; their union should match `lines`."""
    if not require(where, ex, ["path", "lines"]):
        return
    tally("excerpts")
    funcs = ex.get("functions")
    if not isinstance(funcs, list) or not all(isinstance(f, str) and f for f in funcs):
        fail(where, "functions must be a list of declaration names ([] for a whole module)")
        return
    lines = ex["lines"]
    if not (isinstance(lines, list) and len(lines) == 2 and all(isinstance(x, int) for x in lines) and 1 <= lines[0] <= lines[1]):
        fail(where, f"lines {lines} must be [first, last]")
        return
    source = repo.show(head, ex["path"])
    if source is None:
        fail(where, f"{ex['path']} does not exist at {head[:10]}")
        return
    text = source.splitlines()
    if lines[1] > len(text):
        fail(where, f"lines {lines} run past the end of {ex['path']} ({len(text)} lines)")
        return
    a, b = trim_blank(text, *lines)
    if not funcs:
        first, last = trim_blank(text, 1, len(text))
        if lines[0] != 1 or b != last:
            mismatches.append(f"{where}: whole-module excerpt covers lines {lines}, the module runs 1-{last}")
        return
    decls = []
    for f in funcs:
        got = repo.resolve(head, ex["path"], f)
        if isinstance(got, str):
            fail(where, got)
        else:
            tally("excerpt declarations")
            decls.append(got)
    if len(decls) != len(funcs):
        return
    if any(d.chain[:-1] != decls[0].chain[:-1] for d in decls):
        fail(where, f"functions {funcs} do not share an enclosing declaration")
        return
    siblings = repo.siblings(head, ex["path"], decls[0])
    order = [siblings.index(d) for d in decls]
    if order != list(range(order[0], order[0] + len(order))):
        between = [d.name for d in siblings[min(order) : max(order) + 1] if d not in decls]
        fail(where, f"functions {funcs} are not consecutive in source order (between them: {between})")
        return
    if a not in (decls[0].first, decls[0].line) or b != decls[-1].last:
        mismatches.append(
            f"{where}: lines {lines} differ from the union of {funcs}, {decls[0].first}-{decls[-1].last}"
        )


def trim_blank(text: list[str], a: int, b: int) -> tuple[int, int]:
    while a < b and not text[a - 1].strip():
        a += 1
    while b > a and not text[b - 1].strip():
        b -= 1
    return a, b


def check_pr(pr_dir: Path, repo: Repo) -> None:
    where = str(pr_dir)
    parsed = front_matter(pr_dir / "pr.md") if (pr_dir / "pr.md").exists() else fail(where, "no pr.md")
    if not parsed:
        return
    meta, _ = parsed
    pw = f"{where}/pr.md"
    if not require(pw, meta, ["kind", "number", "head", "base", "merge_base", "prepared_at", "session_id", "l1"]):
        return
    if meta["kind"] != "pr":
        fail(pw, f"kind is {meta['kind']}, expected pr")
    if str(meta["number"]) != pr_dir.name:
        fail(pw, f"number {meta['number']} does not match directory {pr_dir.name}")
    check_layers(pw, meta)
    head, base = meta["head"], meta["base"]
    for key in ("head", "base", "merge_base"):
        if not repo.has_commit(meta[key]):
            fail(pw, f"{key} {meta[key]} is not in {repo.root}")
            return
    merge_base = repo.git("merge-base", base, head).stdout.strip()
    if merge_base != meta["merge_base"]:
        fail(pw, f"merge_base is {meta['merge_base'][:10]}, git says {merge_base[:10]}")
    tally("PRs")

    steps = json.loads((pr_dir / "code-path.json").read_text())
    if not isinstance(steps, list) or not steps:
        fail(f"{where}/code-path.json", "must be a non-empty list of steps")
        steps = []
    step_ids = {s.get("id") for s in steps}
    if sorted(step_ids) != list(range(1, len(steps) + 1)):
        fail(f"{where}/code-path.json", f"step ids {sorted(step_ids)} are not 1..{len(steps)}")
    for s in steps:
        sw = f"{where}/code-path.json step {s.get('id')}"
        require(sw, s, ["id", "title", "l1", "node", "excerpts"])
        check_layers(sw, s)
        tally("steps")
        for i, ex in enumerate(s.get("excerpts", []), 1):
            check_excerpt(f"{sw} excerpt {i}", ex, repo, head)

    diagrams = json.loads((pr_dir / "diagrams.json").read_text())
    pr_nodes = check_diagram(f"{where}/diagrams.json pr", diagrams.get("pr"), repo, head, step_ids)
    for s in steps:
        if s.get("node") not in pr_nodes:
            fail(f"{where}/code-path.json step {s.get('id')}", f"node {s.get('node')} is not in the PR diagram")
    for key, d in diagrams.get("steps", {}).items():
        if not key.isdigit() or int(key) not in step_ids:
            fail(f"{where}/diagrams.json", f"step diagram {key} has no step")
        check_diagram(f"{where}/diagrams.json step {key}", d, repo, head, step_ids)

    for n, line in enumerate((pr_dir / "notes.jsonl").read_text().splitlines(), 1):
        if not line.strip():
            continue
        nw = f"{where}/notes.jsonl line {n}"
        note = json.loads(line)
        if not require(nw, note, ["id", "path", "line", "side", "commit", "severity", "status", "who", "l1", "l2", "created", "updated"]):
            continue
        tally("review notes")
        if note["side"] not in SIDES:
            fail(nw, f"side {note['side']} is not one of {sorted(SIDES)}")
        if note["severity"] not in SEVERITIES:
            fail(nw, f"severity {note['severity']} is not one of {sorted(SEVERITIES)}")
        if note["status"] not in STATUSES:
            fail(nw, f"status {note['status']} is not one of {sorted(STATUSES)}")
        if note["status"] == "posted" and not note.get("github_comment_id"):
            warnings.append(f"{nw}: posted note has no github_comment_id")
        commit = note["commit"] if note["side"] == "head" else base
        source = repo.show(commit, note["path"])
        if source is None:
            fail(nw, f"{note['path']} does not exist at {commit[:10]}")
        elif not 1 <= note["line"] <= len(source.splitlines()):
            fail(nw, f"line {note['line']} is outside {note['path']}")
        check_layers(nw, note)

    changed = repo.changed(base, head)
    files = json.loads((pr_dir / "files.json").read_text())
    for path, layers in files.items():
        fw = f"{where}/files.json {path}"
        tally("file descriptions")
        if path not in changed:
            fail(fw, "not a file this PR changes")
        check_layers(fw, layers)


def check_entry(path: Path, wordbase: Path, repo: Repo) -> None:
    parsed = front_matter(path)
    if not parsed:
        return
    meta, body = parsed
    where = str(path.relative_to(wordbase))
    kind = meta.get("kind")
    if kind not in KINDS:
        fail(where, f"kind {kind} is not one of {sorted(KINDS)}")
        return
    if kind == "pr":
        return  # checked with its directory
    tally(f"{kind} entries")
    if kind == "file":
        if not require(where, meta, ["path", "commit", "updated", "by", "l1", "system"]):
            return
        if where != meta["path"] + ".md":
            fail(where, f"path {meta['path']} does not match the entry's location")
        if repo.show(meta["commit"], meta["path"]) is None and not meta.get("deleted"):
            fail(where, f"{meta['path']} does not exist at {meta['commit'][:10]}")
        if not (wordbase / "systems" / f"{meta['system']}.md").exists():
            fail(where, f"system {meta['system']} has no entry")
        check_layers(where, meta)
        check_notes_section(where, body)
    elif kind == "system":
        if not require(where, meta, ["name", "updated", "members"]):
            return
        if where != f"systems/{meta['name']}.md":
            fail(where, f"name {meta['name']} does not match the entry's location")
        for key in ("members", "uses", "used_by"):
            if not isinstance(meta.get(key, []), list):
                fail(where, f"{key} must be a list")
        if "l1" in meta:
            check_layers(where, meta)
        if "diagram" in meta:
            ids = check_diagram(f"{where} diagram", meta["diagram"], repo, meta.get("commit", "HEAD"))
            for other in meta.get("uses", []) + meta.get("used_by", []) + [meta["name"]]:
                if other not in ids:
                    fail(f"{where} diagram", f"system {other} from uses/used_by has no box")
        check_notes_section(where, body)
    elif kind == "reviewer":
        require(where, meta, ["updated"])
        check_notes_section(where, body)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--wordbase", type=Path, default=VIEWER / "wordbase")
    parser.add_argument("--marin", type=Path, action="append", help="Marin checkout(s) to read commits from")
    parser.add_argument("--strict", action="store_true", help="fail when an excerpt's lines differ from its declarations")
    args = parser.parse_args()
    candidates = args.marin or [VIEWER / "marin", Path.home() / "openathena" / "marin"]
    wordbase = args.wordbase.resolve()

    pr_dirs = sorted(p for p in (wordbase / "prs").iterdir() if p.is_dir()) if (wordbase / "prs").exists() else []
    heads = []
    for pr_dir in pr_dirs:
        parsed = front_matter(pr_dir / "pr.md")
        if parsed:
            heads.append(parsed[0].get("head", ""))
    # Use the first checkout that holds every PR head; a fresh clone of main may lack merged PR heads.
    repo = None
    for root in candidates:
        if (root / ".git").exists() and all(Repo(root).has_commit(h) for h in heads if h):
            repo = Repo(root)
            break
    if repo is None:
        raise SystemExit(f"no Marin checkout among {[str(c) for c in candidates]} has every PR head commit")
    print(f"wordbase {wordbase}\nmarin    {repo.root}")

    for pr_dir in pr_dirs:
        check_pr(pr_dir, repo)
    for path in sorted(wordbase.rglob("*.md")):
        if ".git" not in path.parts:
            check_entry(path, wordbase, repo)

    for what, n in sorted(counts.items()):
        print(f"  {n:4d} {what}")
    for w in warnings:
        print(f"WARN  {w}")
    for m in mismatches:
        print(f"MISMATCH  {m}")
    if mismatches and args.strict:
        errors.extend(f"(strict) {m}" for m in mismatches)
    for e in errors:
        print(f"FAIL  {e}")
    if errors:
        print(f"{len(errors)} failures")
        sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main()
