#!/usr/bin/env python3
"""Index prepared seL4 configurations separately, then union compiler records."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from sel4_sources import source_files
from sel4_scip_union import union


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepared", type=Path, required=True)
    parser.add_argument("--indexer", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    prepared = args.prepared.expanduser().resolve()
    manifest = json.loads((prepared / "manifest.json").read_text())
    root = Path(manifest["repository"])
    database = json.loads((prepared / "compile_commands.json").read_text())
    tracked = [p.encode() for p in source_files(root)]

    def digest():
        import os
        result = hashlib.sha256()
        for raw in tracked:
            if raw:
                path = root / os.fsdecode(raw)
                contents = os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes()
                result.update(raw + b"\0" + contents)
        return result.hexdigest()

    if digest() != manifest["sourceSHA256"]:
        raise RuntimeError("seL4 source changed; regenerate the prepared inputs first")
    indexes, provenance = [], []
    for profile in manifest["profiles"]:
        if profile["status"] != "ready":
            continue
        build = prepared / profile["profile"]
        entries = [entry for entry in database if Path(entry["file"]).parent == build]
        if len(entries) != 2:
            raise ValueError("Expected kernel and libsel4 inputs for " + profile["profile"])
        compdb = build / "radiology-compile_commands.json"
        compdb.write_text(json.dumps(entries, indent=2) + "\n")
        output = build / "radiology.scip"
        with (build / "index.log").open("w") as log:
            subprocess.run([str(args.indexer), "--compdb-path", str(compdb), "--index-output-path", str(output),
                            "--supplementary-output-dir", str(build / "scip-logs"),
                            "--show-compiler-diagnostics", "--no-progress-report", "--jobs", str(manifest.get("index_jobs", 1))],
                           cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True)
        log_text = (build / "index.log").read_text()
        if "error:" in log_text:
            raise RuntimeError("Compiler errors: " + str(build / "index.log"))
        data = output.read_bytes()
        indexes.append(data)
        provenance.append({"profile": profile["profile"], "sha256": hashlib.sha256(data).hexdigest()})
        print(profile["profile"] + ": indexed", flush=True)
    merged = union(indexes)
    if digest() != manifest["sourceSHA256"]:
        raise RuntimeError("seL4 source changed during indexing")
    destination = args.output.expanduser().absolute()
    temporary = destination.with_suffix(".scip.tmp")
    temporary.write_bytes(merged)
    temporary.replace(destination)
    destination.with_suffix(".provenance.json").write_text(json.dumps({
        "sourceSHA256": manifest["sourceSHA256"], "inputs": provenance,
        "outputSHA256": hashlib.sha256(merged).hexdigest()}, indent=2) + "\n")
    print(str(len(indexes)) + " configurations merged: " + str(destination), flush=True)


if __name__ == "__main__":
    main()
