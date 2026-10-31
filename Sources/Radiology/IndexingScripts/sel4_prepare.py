#!/usr/bin/env python3
"""Prepare real seL4 compiler inputs while preserving physical source locations.

Run with a Python environment containing seL4's generator dependencies. This
only builds generated headers and the upstream unity-source list, never a
kernel binary. The resulting compilation database is suitable for scip-clang.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tomllib
from sel4_sources import source_files


def run(command, directory, environment, log):
    with log.open("w") as output:
        subprocess.run(command, cwd=directory, env=environment, stdout=output,
                       stderr=subprocess.STDOUT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--clang", type=Path, required=True)
    parser.add_argument("--all-verified", action="store_true")
    parser.add_argument("--extended", action="store_true",
                        help="also cover 32-bit x86/RISC-V and debug/MCS/SMP/VMX branches")
    parser.add_argument("--configuration", type=Path, default=Path(__file__).parent.parent / "IndexingPersonalities/sel4.toml")
    args = parser.parse_args()
    configuration = tomllib.loads(args.configuration.read_text())
    settings = configuration["sel4"]
    root = args.repository.expanduser().resolve()
    for path in settings["required_files"]:
        if not (root / path).is_file():
            raise ValueError("This checkout is not seL4: missing " + path)
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    clang = args.clang.expanduser().absolute()
    environment = dict(os.environ)
    # CMake's upstream LLVM toolchain resolves clang and python3 using PATH.
    environment["PATH"] = os.pathsep.join([
        str(clang.parent), str(Path(os.sys.executable).parent), environment.get("PATH", "")])
    tracked = [p.encode() for p in source_files(root)]

    def source_digest():
        digest = hashlib.sha256()
        for raw in tracked:
            if raw:
                path = root / os.fsdecode(raw)
                contents = os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes()
                digest.update(raw + b"\0" + contents)
        return digest.hexdigest()

    original = source_digest()
    profiles = []
    names = set()
    for profile in settings["profiles"]:
        name = profile["name"]
        if name in names or not re.fullmatch(r"[A-Za-z0-9_-]+", name):
            raise ValueError("Invalid or duplicate profile name: " + name)
        names.add(name)
        if profile.get("group") == "verified":
            if not args.all_verified and name != "X64_verified":
                continue
        elif not args.extended:
            continue
        preset = (root / profile["preset"]).resolve()
        if not preset.is_relative_to(root) or not preset.is_file():
            raise ValueError("Missing seL4 preset: " + profile["preset"])
        flags = ["-D" + value for value in profile.get("defines", [])]
        profiles.append((name, preset, profile["triple"], flags))
    commands, results = [], []
    for name, preset, triple, flags in profiles:
        build = output / name
        build.mkdir(exist_ok=True)
        record = {"profile": name, "preset": str(preset), "flags": flags, "triple": triple}
        last_log = build / "configure.log"
        try:
            run([configuration.get("runtime", {}).get("cmake", "cmake"), "--fresh", "-S", str(root), "-B", str(build), "-G", "Ninja", "-C", str(preset),
                 "-DCMAKE_TOOLCHAIN_FILE=" + str(root / settings["toolchain"]), "-DTRIPLE=" + triple,
                 "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON", *flags], root, environment, build / "configure.log")
            last_log = build / "headers.log"
            run([configuration.get("runtime", {}).get("cmake", "cmake"), "--build", str(build), "--target", *settings["build_targets"], "-j", str(settings["build_jobs"])],
                root, environment, build / "headers.log")
            database = json.loads((build / "compile_commands.json").read_text())
            effective = dict(re.findall(r"^((?:Kernel|Hardware)\w+):[^=\n]+=(.*)$", (build / "CMakeCache.txt").read_text(), re.MULTILINE))
            record["effective"] = {k: effective.get(k) for k in [
                "KernelPlatform", "KernelSel4Arch", "KernelIsMCS", "KernelDebugBuild",
                "KernelEnableSMPSupport", "KernelMaxNumNodes", "KernelNumDomains", "KernelVTX", "KernelIOMMU",
                "KernelArmSMMU", "KernelTk1SMMU", "HardwareDebugAPI", "KernelSyscall", "KernelBenchmarks"]}
            if "-smp" in name and effective.get("KernelEnableSMPSupport") != "ON":
                raise ValueError("Requested SMP was disabled by configuration dependencies")
            entry = next(e for e in database if e["file"] == str(build / settings["unity_source"]))
            # The real build concatenates C text with #line directives. Clang
            # indexes physical locations, so include those exact files instead,
            # retaining the real unity ordering and all compiler flags.
            sources = re.findall(r'^#line 1 "([^"\n]+)"$', (build / settings["unity_source"]).read_text(), re.MULTILINE)
            if not sources or any(not Path(s).is_file() for s in sources):
                raise ValueError("Missing upstream unity-source list")
            wrapper = build / "radiology-kernel.c"
            wrapper.write_text("/* seL4 unity order with original physical source locations. */\n" +
                               "".join("#include " + json.dumps(s) + "\n" for s in sources))
            arguments = shlex.split(entry["command"])
            arguments[arguments.index(entry["file"])] = str(wrapper)
            kernel_command = {"directory": entry["directory"], "file": str(wrapper), "arguments": arguments}
            # Public syscall wrappers are not reached by kernel includes. Use
            # libsel4's own compiler flags and generated ABI headers as well.
            library = next(e for e in database if e["file"] == str(root / settings["library_source"]))
            api_wrapper = build / "radiology-libsel4.c"
            api_wrapper.write_text("".join("#include <" + h + ">\n" for h in settings["api_headers"]) +
                                   "#include " + json.dumps(library["file"]) + "\n")
            library_arguments = shlex.split(library["command"])
            library_arguments[library_arguments.index(library["file"])] = str(api_wrapper)
            # Public syscall headers use GNU `asm`; the library's own tiny C
            # source does not. Enable that dialect for the API consumer probe.
            library_arguments.append("-std=" + settings["api_standard"])
            commands.extend([kernel_command, {"directory": library["directory"], "file": str(api_wrapper), "arguments": library_arguments}])
            record["apiStandard"] = settings["api_standard"]
            record.update(status="ready", sources=[str(Path(s).relative_to(root)) for s in sources])
            print(name + ": ready (" + str(len(sources)) + " C files)", flush=True)
        except (subprocess.CalledProcessError, ValueError, StopIteration) as error:
            record.update(status="failed", error=str(error))
            print(name + ": FAILED; see " + str(build), flush=True)
            if last_log.exists():
                print(last_log.read_text(errors="replace")[-12000:], flush=True)
        results.append(record)
    if source_digest() != original:
        raise RuntimeError("Tracked seL4 source bytes changed during generation")
    if not commands:
        raise RuntimeError("No usable configurations; compilation database was not replaced")
    database_path = output / "compile_commands.json"
    temporary = database_path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(commands, indent=2) + "\n")
    temporary.replace(database_path)
    manifest = {"repository": str(root), "head": None,
                "sourceSHA256": original, "clang": str(clang), "profiles": results, "index_jobs": configuration["clang_jobs"]}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(str(sum(r["status"] == "ready" for r in results)) + "/" + str(len(profiles)) +
          " configurations, " + str(len(commands)) + " translation units ready: " + str(database_path), flush=True)


if __name__ == "__main__":
    main()
