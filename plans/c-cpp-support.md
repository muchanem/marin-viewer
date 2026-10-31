# C and C++ support

## Contract

Radiology bundles official Tree-sitter C 0.24.2 and C++ 0.23.4 grammars,
statically linked through their SwiftPM products. Ten grammar registrations
now load 47 Radiology query files. C++ inherits the common C query directory
and adds C++ patterns. Both provide highlighting, declarations, lexical scopes,
folds and call sites; existing outline, breadcrumbs, function shading, x folding,
references and Critical Lens use those structures without a new reader UI.

`.c` uses C. `.C` uses C++ under the conventional Unix naming rule. C++ also
claims `.cc`, `.cpp`, `.cxx`, `.c++`, `.h`, `.hh`, `.hpp`, `.hxx`, `.h++`,
`.ipp`, `.inl`, `.tpp` and `.tcc`. Ambiguous `.h` defaults to the C++ grammar
to retain classes/templates while accepting common C declarations. Strict
C-only header extensions may still produce a partial parse. Objective-C/CUDA
grammars are outside this change.

Recursive declarator names are resolved by following the parser's declarator
fields, preserving precise selection bytes through pointer/reference returns,
qualified definitions, destructors and operators. Parameters and initializers
cannot become declaration names. Function-pointer variables are excluded from
the callable outline; function-pointer typedefs remain aliases. C++ lambdas own
their calls, separate from the containing function. Unnamed/computed callees
remain explicit unknown sites; no spelling-based semantic edges are added.
C++ `new` and `delete` also remain explicit unknown sites because they can
invoke user code without a directly resolvable callee token. Implicit calls
from ordinary object lifetime and macro expansion are not a complete call graph.

## SCIP

The existing scip-clang adapter now offers managed installation of the upstream
0.4.0 Apple Silicon macOS binary. The pinned SHA-256 digest is
`ff042fbc8a029f09f4b69fc7692e290e21c52923593207ee52d4e7439473ec64`,
verified against the [upstream release API](https://api.github.com/repos/sourcegraph/scip-clang/releases/tags/v0.4.0).
Downloads stage beside the installed executable, verify before execution,
check `--version`, then replace the executable. Failed downloads preserve an
existing installation. Intel users retain manual tool discovery.

Indexing prefers a real `compile_commands.json` with the configured compiler
flags, include paths and generated inputs. Without one it automatically runs
source-only best-effort indexing; no build setup is required. Besides visible database paths,
the service checks root/build/out/Debug/Release/cmake-build-debug/
cmake-build-release locations, including up to 64 CMake manifest directories.
This runs on the indexing actor and never builds the attached checkout.
PR snapshots do not discover untracked or ignored build inputs.
Discovered paths are temporary inspection inputs, so removing a database and
reindexing reports its absence rather than retaining a stale strategy.
The adapter chooses the shallowest real database, keeps the repository root as
SCIP project root, and limits worker parallelism to four. With no database,
it generates a temporary one using GNU C11/C++20 and inferred repository include
paths, with a distinct versioned strategy marker. This mode always persists
Best effort coverage, including cache/reuse. A real database appearing later
changes the strategy and triggers regeneration. See
[the fallback contract](clang-best-effort.md) for defaults, bounds and validation.

Compiler diagnostics are requested. Missing source documents or reported
compiler errors produce persisted Partial coverage, including on cache hits;
successful process exit alone cannot establish full coverage. SCIP output and
supplementary logs live in temporary paths and are cleaned after the run.
Document positions retain the existing UTF-8 default. Cache generation,
source-byte identity and snapshot-only document publication remain intact.

scip-clang 0.4.0 has an upstream symbol gap for functions declared inside
`extern "C"` linkage blocks: its
[SymbolFormatter](https://github.com/sourcegraph/scip-clang/blob/v0.4.0/indexer/SymbolFormatter.cc)
does not support LinkageSpecDecl contexts. The checked-in fixture demonstrates
missing C++-to-C occurrences while its C caller and definition work. Radiology
keeps absent occurrences unavailable. A compiler's emitted document count does
not prove every construct inside that document has semantic coverage.

## tkfiasco boundary

`/Users/tqbf/codebase/tk/tkfiasco` was inspected read-only. It includes a Linux
GCC cross-build, Fiasco's custom source preprocessor, and no compilation
database or retained generated build directories. Grammar and best-effort SCIP
support work after relaunch. Its configured build database and generated inputs
can improve coverage; they are optional.

For Make, capture the real build with Bear on the build host. For CMake,
configure with `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`. A copied database must
refer to paths and compiler inputs available on this Mac before Radiology can
index it. Capturing only preprocessed Fiasco translation units may describe
generated files rather than the original `INTERFACE` / `IMPLEMENTATION`
sources; navigation to absent generated files is filtered out. These custom
source directives can also cause Tree-sitter parse errors, while recoverable
classes/functions/folds still appear. No flags or source maps are fabricated.

## Validation and handoff

`CSyntaxTests` covers both grammars, recursive declarators, constructors/
destructors/operators, templates, Unicode call offsets, mixed headers and
lambda ownership. Registry/query tests cover all ten grammars and resources.
`CScipTests` uses an actual scip-clang fixture for overload identities, C
definition/references and exact reader Back. Its installed-tool test runs the
real service in a disposable workspace, checks hidden database discovery,
source preservation, honest partial coverage and cached UTF-8 semantics.
`CRealDataProbe` is opt-in with `RADIOLOGY_CPP_PROBE_ROOT` and parses real
checkout samples without source/build writes.

The only SwiftUI addition is contextual compilation-database guidance inside
the existing indexing popover, using Theme.Fonts.meta and secondary emphasis.
SwiftUI-pro guidance applied before and after code decisions; native macOS
popover conventions and the existing typography scale are retained.
See the newest PROGRESS.md entry for actual final test/build/probe evidence.

Final gates (2026-10-13): **301 tests /66 suites pass** sequentially, including
the installed compiler service and opt-in tkfiasco probe; make check/build,
strict deep codesign, shell syntax and diff checks pass. Empty-environment
packaged verification from /tmp loads all ten grammars,47 queries and four
indexing scripts. tkfiasco probe reads 22,268 eligible files and parses13
samples; thread.cpp yields143 declarations/129 folds/528 call sites while
honestly retaining parse errors. Its Git status remains clean. No shared-reader
restart or physical clicks were performed. Relaunch build/Radiology.app to
load the new registry. The original grammar round did not generate a tkfiasco
SCIP index; the subsequent best-effort round supersedes that prerequisite.
See newest PROGRESS.md and clang-best-effort.md for current validation.
