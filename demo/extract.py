"""Build demo JSON for PR 10640: full-context diffs, blame, and a symbol table."""
import json, re, subprocess, sys
REPO = "/Users/k3sc0re/openathena/marin"
BASE, HEAD = "8a92f90382559206b03ead1afbbd32c35f68fcff", "01a8bb8f0bea2dde1de90274ed695c25147b9f06"
OUT = sys.argv[1]

def git(*args):
    return subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True, check=True).stdout

names = git("diff", "--name-status", BASE, HEAD).splitlines()
files = []
symbols = {}
commits = {}
for row in names:
    status, path = row.split("\t")[0], row.split("\t")[-1]
    entry = {"path": path, "status": status}
    src = path.startswith("lib/shellbox/src/") or path == "lib/shellbox/README.md"
    if src:
        diff = git("diff", "-U100000", BASE, HEAD, "--", path).splitlines()
        lines, old, new, started = [], 0, 0, False
        for d in diff:
            if d.startswith("@@"):
                m = re.match(r"@@ -(\d+)(?:,\d+)? \+(\d+)", d)
                old, new, started = int(m.group(1)), int(m.group(2)), True
                continue
            if not started or d.startswith("\\"):
                continue
            tag, text = d[:1], d[1:]
            if tag == " ":
                lines.append(["c", old, new, text]); old += 1; new += 1
            elif tag == "-":
                lines.append(["d", old, None, text]); old += 1
            elif tag == "+":
                lines.append(["a", None, new, text]); new += 1
        entry["lines"] = lines
        blame = git("blame", "--porcelain", HEAD, "--", path).splitlines()
        per_line, cur, meta = [], None, {}
        i = 0
        while i < len(blame):
            head = blame[i].split()
            sha = head[0]; i += 1
            while i < len(blame) and not blame[i].startswith("\t"):
                k, _, v = blame[i].partition(" ")
                if sha not in commits:
                    meta.setdefault(sha, {})[k] = v
                i += 1
            i += 1
            if sha not in commits and sha in meta:
                m = meta[sha]
                commits[sha] = {"author": m.get("author", ""), "time": int(m.get("author-time", 0)), "summary": m.get("summary", "")}
            per_line.append(sha[:10])
        entry["blame"] = per_line
        head_src = git("show", f"{HEAD}:{path}")
        for n, line in enumerate(head_src.splitlines(), 1):
            m = re.match(r"(\s*)(?:async\s+)?(def|class)\s+([A-Za-z_]\w*)", line)
            if m and len(m.group(1)) <= 4 and not m.group(3).startswith("__"):
                symbols.setdefault(m.group(3), []).append([path, n])
    else:
        stat = git("diff", "--numstat", BASE, HEAD, "--", path).split()
        entry["add"], entry["del"] = int(stat[0]), int(stat[1])
    files.append(entry)
commits = {k[:10]: v for k, v in commits.items()}
json.dump({"base": BASE, "head": HEAD, "files": files, "symbols": symbols, "commits": commits}, open(OUT, "w"))
print(len(files), sum(len(f.get("lines", [])) for f in files), len(symbols), len(commits))
