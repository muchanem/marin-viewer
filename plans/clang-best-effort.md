# C/C++ indexing without a compilation database

The user explicitly requested best-effort indexing without build information
on 2026-10-13, superseding the earlier prerequisite. Radiology now automatically
selects scip-clang for C/C++ repositories without compile_commands.json.
No build is run and no source files or object binaries are written to the
attached checkout.

## Behavior

Real discovered compilation databases retain priority. Otherwise,
ClangFallbackDatabase writes a temporary JSON database beside the temporary
SCIP output. Every available C/C++ translation unit gets an entry; there is
no translation-unit cap. Header-only repositories index their headers instead.
Headers in other repositories are covered as the compiler follows includes.

Each entry uses the host Clang driver, explicit GNU C11 or GNU C++20,
warnings suppressed, and a five-error diagnostic limit. `.C` remains C++.
Include search starts in the source's ancestors and existing include/inc/src
directories, then follows literal include directives through repository headers.
Resolution prefers headers near their including file, considers up to eight
matching header locations, and infers at most 64 include directories per unit
with a 128-header recursion bound. Include directives only infer paths; they
cannot invent declarations, headers, macros or symbol edges. Shared header
directory discovery is memoized, and cancellation checks interrupt traversal.
Preparation runs in a cancellable detached utility task so the indexing actor
remains responsive to repository changes.

scip-clang parses original source files with those defaults and reports compiler
identities at their original byte coordinates. No source stripping, fake
declarations, or position remapping is introduced. Missing headers can still
permit useful recovered declarations/calls; tests demonstrate this through the
actual compiler. Unknown/missing occurrences stay unavailable. The temporary
database, supplementary logs and index staging files are cleaned after normal
completion or task cancellation; cached indexes live outside the checkout.
Four compiler workers and normal tool progress bound concurrency and expose
progress on large repositories. Indexing can be cancelled with existing controls.

## Coverage and freshness

The strategy's evidence contains a versioned defaults marker. It differs from
real-database evidence, so adding/removing a build database changes strategy
identity and invalidates incompatible cache records. The source digest still
covers actual repository inputs. Synthetic inputs never enter the Files tree.
PR snapshots use their own source root and exact source inventory for generated
entries, without borrowing an ignored working-tree build configuration.

`SemanticCoverageCapability.bestEffort` always produces Partial status even
if every source document is emitted without compiler errors. Best effort labels
and the explanation persist on generation, cached reload and reuse. The native
indexing popover uses existing Theme.Fonts.meta/secondary typography. The absence
of a database is therefore a visible assumption, not a reason to withhold all
semantic navigation.

Defaults cannot establish the actual target, defines, language settings or build
variants. Inactive branches, include ambiguities and macro/custom preprocessing
can omit or misinterpret code. Symbols from separate programs/variants may have
multiple candidate definitions. tkfiasco's Fiasco INTERFACE/IMPLEMENTATION source
dialect remains partially parseable, and generated declarations may be missing.
The upstream extern-C symbol gap described in c-cpp-support.md also remains.
A real build database improves coverage whenever the reader has one.

## Verification

ClangFallbackTests checks deterministic language defaults, `.C`, inferred
cross-directory headers, real database priority and header-only fallback.
A real compiler service test resolves a cross-file C++ call despite an absent
header, preserves source bytes, cleans synthetic inputs and retains Best effort
on cache reload. CScipTests checks real database removal → fallback and real
database restoration → configured indexing, with document coverage changing
accordingly. CRealDataProbe's optional full-root compiler probe records actual
tkfiasco coverage without writing its sources. Final gates and measurement are
in the newest PROGRESS.md entry.

SwiftUI-pro guidance applied before and after code decisions; macOS interaction
and typography retain the existing indexing popover/controls and type scale.

## Actual tkfiasco acceptance

Without build inputs, the full run attempted 11,513 translation units and
published 15,669 tracked documents, 523,683 symbols and 2,820,466 occurrences.
The inventory contains 22,268 eligible C/C++ files; 7,023 were uncovered, while
some additional included fragments also emit SCIP documents. thread.cpp has 467
occurrences with zero unmapped byte ranges. Cold indexing/publication took
321.438 seconds; fresh actor cache load took 18.144 seconds with no compiler
invocation and cached Best effort retained. Source digests match before/after,
and the checkout's Git status stays clean. The normal app cache is primed with
the verified 161,502,231-byte index; relaunch is required to load the upgraded app.
The full 305-test suite passes, including cancellation and configuration
transitions. Eight final targeted tests also pass; compile/signed build,
strict deep signing, diff checks and empty-environment packaged resources
(10 grammars,47 queries,4 scripts) pass. Built 17:56:17 CDT. Newest PROGRESS.md
records exact logs and the primed cache location.
