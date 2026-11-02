# Vendored Tree-sitter external scanners

`tree-sitter-javascript` and `tree-sitter-python` publish SwiftPM manifests that
decide whether to compile their external scanner with
`FileManager.default.fileExists(atPath: "src/scanner.c")`. That path is relative
to the manifest process's working directory, not the package directory, so the
check fails and the scanner is silently dropped, leaving
`tree_sitter_<lang>_external_scanner_*` undefined at link time. Both grammars
depend on their scanner for correctness — Python's entire INDENT/DEDENT/NEWLINE
layer and JavaScript's regex/template/ASI handling live there — so the sources
are vendored here instead of patching upstream manifests.

Keep these files in lock-step with the grammar versions pinned in
`Package.swift`. A scanner's `TokenType` enum must match the external-token
order baked into the matching generated `parser.c`.

| File | Upstream | Version | Path | Licence |
| --- | --- | --- | --- | --- |
| `javascript_scanner.c` | [tree-sitter/tree-sitter-javascript](https://github.com/tree-sitter/tree-sitter-javascript) | `v0.25.0` | `src/scanner.c` | MIT, © 2014 Max Brunsfeld |
| `python_scanner.c` | [tree-sitter/tree-sitter-python](https://github.com/tree-sitter/tree-sitter-python) | `v0.25.0` | `src/scanner.c` | MIT, © 2016 Max Brunsfeld |
| `vendor/tree_sitter/parser.h` | tree-sitter runtime headers shipped with both grammars (byte-identical) | `v0.25.0` | `src/tree_sitter/parser.h` | MIT |
| `vendor/tree_sitter/array.h` | as above | `v0.25.0` | `src/tree_sitter/array.h` | MIT |
| `vendor/tree_sitter/alloc.h` | as above | `v0.25.0` | `src/tree_sitter/alloc.h` | MIT |

`include/GrammarScanners.h` is Radiology's own placeholder: SwiftPM needs a
public headers directory, and the scanner entry points are referenced by each
grammar's generated `parser.c`, never from Swift.
