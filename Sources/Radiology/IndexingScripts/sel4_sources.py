"""Inventory source inputs in both a Git checkout and an isolated snapshot."""
import os
import subprocess


def source_files(root):
    if (root / ".git").exists():
        result = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root)
        paths = [os.fsdecode(p) for p in result.split(b"\0") if p]
    else:
        paths = []
        for directory, folders, files in os.walk(root, followlinks=False):
            relative = os.path.relpath(directory, root)
            for name in folders[:]:
                path = root / relative / name
                if path.is_symlink():
                    paths.append(str(path.relative_to(root)))
                    folders.remove(name)
            paths.extend(str((root / relative / name).relative_to(root)) for name in files)
    excluded = {".git", ".build", "build", "dist", "__pycache__"}
    return sorted({p for p in paths if not any(part in excluded for part in p.split("/")) and not p.endswith(".pyc")})
