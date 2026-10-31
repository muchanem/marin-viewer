#!/usr/bin/env python3
"""CLI entry point for the same seL4 tooling bundled with Radiology."""
from pathlib import Path
import runpy
import sys
resources = Path(__file__).resolve().parents[1] / "Sources/Radiology/IndexingScripts"
sys.path.insert(0, str(resources))
runpy.run_path(str(resources / "sel4_index.py"), run_name="__main__")
