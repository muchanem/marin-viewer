"""Compatibility imports for the bundled SCIP union implementation."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Sources/Radiology/IndexingScripts"))
from sel4_scip_union import fields, message, union, value_of, varint
