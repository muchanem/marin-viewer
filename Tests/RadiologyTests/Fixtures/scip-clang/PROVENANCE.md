# C/C++ SCIP fixture

Generated on 2026-10-13 from exactly these four source files in a disposable
`/tmp/radiology-clang-fixture` copy using Sourcegraph scip-clang 0.4.0,
Clang/LLVM `2078da43e25a4623cab2d0d60decddf709aaea28`. The Apple Silicon
binary's upstream release digest is
`ff042fbc8a029f09f4b69fc7692e290e21c52923593207ee52d4e7439473ec64`.

The temporary compilation database contains three entries with that copy as
`directory`, `src/math.c` / `src/reader.c` / `src/reader.cpp` as `file`, and arguments
`[<xcrun --find clang>, -std=c11 / -std=c++20, -Isrc, -c, <file>, -o, <temporary object>]`.
No external dependencies, generated sources, or source edits are required.

Command, from the copy's root:
`scip-clang --compdb-path compile_commands.json --index-output-path index.scip --supplementary-output-dir logs --no-progress-report --show-compiler-diagnostics --jobs 2`.
Three translation units indexed, zero errored TUs, four source documents.

Tests decode the checked-in index for overload identity, C and C++
definition/reference navigation and UTF-8 positions after `café 🚀`.
An additional service test generates an index in a fresh copy when scip-clang
is installed, verifies hidden build database discovery, source preservation,
partial coverage and cached UTF-8 semantics. There is no checked-in compilation
database with stale absolute build paths.

scip-clang 0.4.0's SymbolFormatter does not support LinkageSpecDecl contexts:
the C++ `extern "C"` declaration and its calls to `add` are absent. The C
definition and C caller are present. Tests assert that this missing C++
occurrence stays unavailable rather than substituting a spelling match.
