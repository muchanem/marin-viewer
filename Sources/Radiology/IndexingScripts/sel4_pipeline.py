#!/usr/bin/env python3
"""TOML-driven, cancellable seL4 preparation and compiler-union pipeline."""
import sys
if sys.version_info < (3, 11):
    raise SystemExit("seL4 indexing requires Python 3.11 or later (standard tomllib support).")
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tomllib


def executable(candidate):
    expanded = os.path.expanduser(candidate)
    path = shutil.which(expanded)
    return Path(path) if path else None


def runtime_python(runtime, tools):
    probe = ("import importlib,importlib.metadata,json,sys; "
             "[importlib.import_module(m) for m in json.loads(sys.argv[1])]; "
             "assert all(importlib.metadata.version(k)==v for k,v in json.loads(sys.argv[2]).items())")
    modules = json.dumps(["tomllib", *runtime["python_imports"]])
    versions = {}
    for package in runtime["python_packages"]:
        name, separator, version = package.partition("==")
        if not separator or not name or not version:
            raise ValueError("python_packages must contain exact name==version pins")
        versions[name] = version
    pins = json.dumps(versions)
    for candidate in runtime["python_candidates"]:
        python = executable(candidate)
        if python and subprocess.run([str(python), "-c", probe, modules, pins], stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL).returncode == 0:
            return python
    # Provision only an app-owned environment. No global Python packages change.
    tools.mkdir(parents=True, exist_ok=True)
    with (tools / "sel4-python.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        venv = tools / "sel4-python"
        python = venv / "bin/python3"
        if not python.exists():
            print("Creating the seL4 Python environment…", flush=True)
            subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
        if subprocess.run([str(python), "-c", probe, modules, pins], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode:
            print("Installing seL4 generator dependencies…", flush=True)
            subprocess.run([str(python), "-m", "pip", "install", "--disable-pip-version-check",
                            *runtime["python_packages"]], check=True)
        subprocess.run([str(python), "-c", probe, modules, pins], check=True)
        return python


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ["repository", "configuration", "indexer", "output", "artifacts", "tools-directory"]:
        parser.add_argument("--" + option, type=Path, required=True)
    args = parser.parse_args()
    configuration = tomllib.loads(args.configuration.read_text())
    if configuration.get("schema_version") != 1 or configuration.get("engine") != "sel4":
        raise ValueError("Invalid seL4 personality engine or schema_version")
    settings, runtime = configuration["sel4"], configuration["runtime"]
    for name in settings["required_files"]:
        if not (args.repository / name).is_file():
            raise ValueError("This checkout is not seL4: missing " + name)
    tool_directories = []
    for name in ["cmake", "ninja", "dtc"]:
        tool = executable(runtime[name])
        if not tool:
            raise ValueError("seL4 indexing requires " + name + ": " + runtime[name])
        tool_directories.append(str(tool.parent))
    clang = None
    for candidate in runtime["clang_candidates"]:
        tool = executable(candidate)
        if not tool:
            continue
        result = subprocess.run([str(tool), "--print-targets"], capture_output=True, text=True)
        targets = set(re.findall(r"^\s+(\S+)\s+-", result.stdout, re.MULTILINE))
        if result.returncode == 0 and set(runtime["required_clang_targets"]).issubset(targets):
            clang = tool
            break
    if clang is None:
        raise ValueError("No configured Clang supports all requested targets. Install Homebrew LLVM or edit clang_candidates.")
    python = runtime_python(runtime, args.tools_directory)
    environment = dict(os.environ)
    environment["PATH"] = os.pathsep.join([str(clang.parent), str(python.parent), *tool_directories, environment.get("PATH", "")])
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    environment["PYTHONUNBUFFERED"] = "1"
    scripts = Path(__file__).parent
    print("Preparing seL4 configurations from " + args.configuration.name + "…", flush=True)
    subprocess.run([str(python), "-u", str(scripts / "sel4_prepare.py"), str(args.repository),
                    "--configuration", str(args.configuration), "--output", str(args.artifacts),
                    "--clang", str(clang), "--all-verified", "--extended"], env=environment, check=True)
    manifest = json.loads((args.artifacts / "manifest.json").read_text())
    failed = [p["profile"] for p in manifest["profiles"] if p["status"] != "ready"]
    if failed:
        raise ValueError("seL4 configurations failed to prepare: " + ", ".join(failed))
    print("Indexing each seL4 configuration separately…", flush=True)
    subprocess.run([str(python), "-u", str(scripts / "sel4_index.py"), "--prepared", str(args.artifacts),
                    "--indexer", str(args.indexer), "--output", str(args.output)], env=environment, check=True)
    print("seL4 configuration union complete.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit("seL4 indexing failed: " + str(error)) from error
