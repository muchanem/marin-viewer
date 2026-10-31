# SCIP indexing and semantic navigation

Radiology generates its own SCIP indexes with real language indexers, caches
them outside the repository, and turns them into Go to Definition, Find
References, ⌘T symbol search, and a ⌘-hover affordance. There is no language
server. Tree-sitter structure and ripgrep search keep working while an index is
missing, building, stale, or failed.

Rust trait implementations are derived before semantic publication and cached
per exact source/occurrence digest. The immutable index gains a trait-to-block
lookup using Tree-sitter impl headers resolved to SCIP identities; rust-analyzer
emits no explicit implementation relationships. Stale contributions are excluded
and source blobs are verified before activation. See
[rust-trait-implementations.md](rust-trait-implementations.md) for cache,
coverage, inspector behavior and measured performance.

This document records the architecture, the decisions behind it, what is
supported, and what is not. `plans/scip-ui-handoff.md` is the native UI test
handoff; `PROGRESS.md` carries validation evidence.

## Primary sources

- `scip.proto` from `github.com/sourcegraph/scip` (fetched 2026-10-03). Field
  numbers, `SymbolRole` bits, `SymbolInformation.Kind`, `PositionEncoding`, and
  the typed `single_line_range`/`multi_line_range` fields (8–11) come from it.
  The deprecated packed `range` form (three or four `int32`) is still what
  rust-analyzer emits, so both are decoded; typed ranges take precedence.
- rust-analyzer `crates/rust-analyzer/src/cli/flags.rs`: `rust-analyzer scip
  <path> [--output] [--config-path] [--exclude-vendored-libraries]`.
- scip-go README (`github.com/scip-code/scip-go`), scip-typescript and
  scip-python npm READMEs and `index --help`, scip-clang README and `--help`
  from the v0.4.0 arm64 macOS binary. Every flag Radiology passes was checked
  against the installed tool's own help output on this machine.

## Architecture

```
RepositorySnapshot ─► SemanticIndexService (actor)
                        │  inspect build files → IndexingStrategy list
                        │  cache metadata + fingerprint → Current / Possibly Stale
                        │  ToolProvisioner: locate, --version, install
                        │  IndexerProcess: posix_spawn, own process group, file-backed I/O
                        │  SCIPDecoder → SCIPIndex (wire model)
                        ▼
                  SemanticPublication { SemanticIndex, status, outcomes, metadata }
                        ▼  (generation-guarded, atomic)
                  SemanticModel (@Observable @MainActor)
                        │  DocumentSemantics for the open buffer (bytes)
                        │  caretTarget, references, ⌘T matches
                        ▼
      AppModel+Semantics: goToDefinition / findReferences / navigate(toDefinition:)
                        ▼
      ReaderTextView: ⌘-hover underline, ⌘-click, context menu   ·   ContextInspectorView (Context regions)
      SemanticStatusView (footer + diagnostics popover)         ·   SymbolSearchSheet (⌘T)
```

### Layers and files

| Layer | Files | Notes |
| --- | --- | --- |
| Wire decoding | `Semantic/SCIP/ProtobufReader.swift`, `SCIPIndex.swift` | Hand-written protobuf reader. Unknown fields are skipped (rust-analyzer sets a field the current schema reserves). No protobuf dependency. |
| Normalized model | `Semantic/SemanticIndex.swift`, `SemanticSymbol.swift` | Immutable `SemanticIndex`: documents, symbols, definitions, references, ⌘T entries. `SemanticSymbolID` namespaces `local N` symbols per document. |
| Byte boundary | `Source/SourceRange.swift`, `Semantic/DocumentSemantics.swift` | The only place SCIP line/column meets `SourceBuffer`. UTF-8/16/32 columns → canonical bytes with out-of-bounds rejection. |
| Queries | `Semantic/SemanticQueryWorker.swift`, `SymbolSearch.swift` | Off-main: per-file byte mapping, destination resolution, references with line text, ranked symbol search. |
| Indexing | `Semantic/Indexing/*` | Strategy detection, adapters, provisioning, cache, fingerprints, process launcher, orchestrator. |
| Model | `Semantic/SemanticModel.swift`, `AppModel+Semantics.swift` | Main-actor state and navigation entry points. |
| UI | `UI/SemanticStatusView.swift`, `ContextInspectorView.swift` and the `Context/` model (see plans/context-sidebar.md), `SymbolSearchSheet.swift`, `Source/ReaderTextView.swift` | Footer status and popover, Symbol inspector pane, ⌘T sheet, hover/click/menu. |

## Decisions and alternatives

**Own protobuf reader instead of SwiftProtobuf.** The SCIP schema is small and
stable; a 150-line wire reader avoids a code-generation step, a large
dependency, and schema-version coupling. Unknown fields are skipped, which is
how the rust-analyzer output (older `Document`-typed signature field) decodes
cleanly. Alternative rejected: shelling out to `scip print --json`, which would
add a tool dependency and a JSON round trip for every load.

**Coordinates convert lazily, against the file on screen.** Occurrences stay in
indexer coordinates inside `SemanticIndex`. When a file opens,
`DocumentSemantics.make` converts that document's occurrences to byte ranges
against the loaded `SourceBuffer`. Destinations convert when the destination
file is read, immediately before the jump. Anything that does not fit the
current bytes is dropped and counted (`unmappedCount`), so a stale index never
manufactures a position. Alternative rejected: converting the whole index at
load, which would read every indexed file up front and still go stale.

**Encoding precedence.** `Document.position_encoding` wins. When unspecified,
`Metadata.text_document_encoding` is consulted, then the adapter's declared
default (UTF-8 for rust-analyzer, scip-go, scip-clang; UTF-16 for
scip-typescript and scip-python, which are TypeScript programs), then UTF-8.
Multi-line ranges and both typed and packed range forms are handled.

**Caret resolution rules.** Occurrences containing the byte are collected,
half-open. Multi-line occurrences are excluded as caret targets because
rust-analyzer emits a whole-file module definition. Among the narrowest hits, a
symbol with an in-repository definition wins, then a repository-wide symbol
over a document-local one (Rust field shorthand binds both on one identifier).
A definition the caret already sits on is not a jump target but still shows in
the inspector with its reference count. Symbols defined only outside the
repository (std, core, npm packages) resolve to a symbol with no destination:
no hover affordance, and Go to Definition reports "defined outside this
repository" instead of guessing.

**Index generation is app-owned, out of process, in a process group.**
`IndexerProcess` uses `posix_spawn` with `POSIX_SPAWN_SETPGROUP`, so
cancellation can `killpg` the indexer and the build tools it spawns (`cargo`,
`tsc`, `go list`). stdout and stderr go to temporary files, never pipes, so a
chatty tool cannot deadlock; only the last 64 KB of each is kept. Progress is
the last stderr line, polled every 400 ms. Alternative rejected: `Process`,
which cannot set a process group and leaves grandchildren alive on terminate.

**Tool provisioning lives in Radiology's directory.** Managed installs go to
`~/Library/Application Support/Radiology/tools/` (`go/bin` as GOBIN, `npm/<pkg>`
as an npm prefix). The exception is rust-analyzer, which is a rustup component
and installs into the active toolchain with `rustup component add
rust-analyzer`; that is the only supported distribution and the component is
what rustup's own `rust-analyzer` proxy expects. Installation is user-initiated
from the diagnostics popover (an **Install** button appears when a tool is
missing and a plan exists); nothing is downloaded or installed silently.
Version checks are real subprocess runs with a 20-second timeout: the rustup
proxy exists even when the component does not, and only `rust-analyzer
--version` succeeding counts as installed.

**rust-analyzer runs on the real project without build scripts or proc macros.**
A reader should not compile a dependency tree to browse it. The config written
to the tools directory disables build scripts and proc-macro expansion. Every
strategy gets its own nested JSON config. Along with `cargo.features = "all"`,
Radiology parses `[features]` from the real project and workspace-member
manifests and supplies each non-default feature as an unquoted `cargo.cfgs`
entry (`feature=name`). This keeps genuine cfg-gated modules visible when
rust-analyzer's Cargo loader falls back to `--no-deps`. Code generated by build
scripts or derive macros is not resolved; handwritten code is. No manifest or
source tree is synthesized.

If stderr says Cargo metadata failed or `--no-deps` was used, the result is
persisted and shown as **Partial / sourceOnlyNoDeps**, with the first Cargo
error and bounded important diagnostics. It is not Current even when the tool
exits zero. Intra-crate definitions, references, and symbol search are real;
dependency/cross-crate types are explicitly not claimed. Coverage compares
every project source path with emitted documents and lists each omission as
orphan, inactive configuration, excluded vendored source, or unknown.

**Mixed-language repositories.** Every adapter proposes strategies for the
top-most project directories it recognizes (`Cargo.toml`, `go.mod`,
`tsconfig.json` or `package.json`, Python project files, `compile_commands.json`).
Strategies are ordered by project depth, then registry order, and capped at
32 so substantial monorepos are covered while work remains bounded; skipped projects are
listed in the popover. Each strategy runs sequentially and caches to its own
file; documents from nested projects are prefixed with the project directory
when merged. Languages present with no adapter are named in the popover.

**Freshness.** `index-metadata.json` records the canonical root, HEAD commit
(when Git exists), a working-tree fingerprint (path, size, mtime of every
discovered file), a build fingerprint (names and contents of build files),
indexer versions, command lines, and timestamps. On open the cached index is
loaded first; if the fingerprint matches, the state is **Current** and no tool
runs. If not, the cache is published as **Possibly Stale** with the reason, and
regeneration starts. Reload Repository (⌘R) re-inspects. There is no filesystem
watcher yet; that remains the later milestone, and the freshness check is
repository-level and coarse by design.

**History.** A semantic jump records the exact departure byte: if the current
entry is an ordinary file visit it is updated to the click or caret position;
if it is a pinned structural anchor, the departure is appended after it. The
destination is then visited and highlighted with the existing transient
accent. Back (⌘[) therefore returns to the exact prior byte, and pinned outline
anchors are preserved.

## Support matrix (verified on this machine, 2026-10-03)

| Adapter | Detects | Tool and version checked | Install path | Status |
| --- | --- | --- | --- | --- |
| rust-analyzer | `Cargo.toml` + `.rs` | `rust-analyzer 1.98.1 (48a229ce 2026-09-01)` via rustup component | `rustup component add rust-analyzer` | Generates; end-to-end tests pass on the fixture crate and through the app |
| scip-go | `go.mod` + `.go` | `scip-go 0.2.7` (`go install github.com/scip-code/scip-go/cmd/scip-go@v0.2.7`, verified in a scratch GOBIN) | `go install` into tools/go/bin | Adapter and provisioning implemented; no Go fixture indexed end to end yet |
| scip-typescript | `tsconfig.json`, else `package.json` + scripts | `@sourcegraph/scip-typescript 0.4.0` (verified `--version` and `index --help` under Node 21.6.2; upstream states Node 22/24 support) | `npm install --prefix tools/npm/scip-typescript` | Adapter and provisioning implemented; `--infer-tsconfig` for JS; not run end to end yet |
| scip-python | `pyproject.toml`/`setup.py`/`setup.cfg`/`requirements.txt` + `.py` | `@sourcegraph/scip-python 0.6.6` (verified `--version`, `index --help`); requires Python 3.10+, this machine has 3.9.1 | `npm install --prefix tools/npm/scip-python` | Adapter and provisioning implemented; expected to fail here with an inspectable diagnostic |
| scip-clang (updated 2026-10-13) | C/C++ sources; real `compile_commands.json` takes priority, including hidden build directories | `scip-clang 0.4.0` arm64 macOS release, actual compiler fixture/service checked | Managed tools/bin binary with pinned upstream release SHA-256; manual discovery on Intel | Automatic source-only defaults without a database, always Best effort/Partial. Definitions/references/Back, overload/UTF-8 identity and cache/config transitions tested; extern-C gaps remain. See clang-best-effort.md and c-cpp-support.md |
| Kotlin/Java Gradle (added 2026-10-07) | Gradle settings/build files + `.kt`/`.java` | scip-java compiler source `9f288dd339c7`, built as `0.13.1-radiology-9f288dd339c7` | `tools/kotlin-scip/distribution`, managed source build with JDK17+ | Kotlin2.4.20/AGP9.4.1/Gradle9.7.1 actual PR758 compilation and JVM fixture pass; caret/references/definitions/Back tested in PR After. Build failures retain Partial. See kotlin-semantic-indexing.md; physical UI unverified |
| Swift | — | — | — | No SCIP indexer exists; reported as unsupported |

Nothing is claimed for languages without an adapter. Tree-sitter outlines and
ripgrep search remain available for all of them.

## States

| State | Meaning | Navigation |
| --- | --- | --- |
| No Index | No strategy applies, or nothing has been produced | Local structure and search only |
| Indexing | Inspecting, loading cache, installing, or running a tool (progress message, step n of m) | Cached index, if any, stays usable |
| Current | Fingerprint matches the cached index | Full |
| Partial | One or more usable indexes are dependency-degraded or another strategy failed | Covered documents remain navigable; capability, warnings, missing files, and failures are inspectable |
| Possibly Stale | Cache loaded but files, build files, or HEAD changed | Full, with unmapped occurrences dropped and counted |
| Failed | A tool is missing, exited nonzero, or produced no documents | Previous index stays usable; popover shows tool, version, command, exit status, stderr/stdout tails, Install/Reindex |

## Limits in this cut

- Hover shows only the underline and pointing hand; there is no preview popup.
- Multiple definitions: the first is followed; all are listed in the Symbol
  inspector as clickable rows.
- Freshness is checked on open, Reload Repository, and Reindex; there is no
  file watcher or timer.
- Only the first 32 strategies run; the rest are listed as skipped.
- References are not paginated; very large symbols produce long lists.
- `references` counts come from the index and include occurrences whose files
  may have changed; the Find References result reports the unmapped count.

## Revision indexes and exact-bytes reuse (pull request review)

A pull request's After snapshot is indexed like a repository, with
`IndexOpenOptions`: a flat `IndexCache` at
`<repo-cache>/revisions/<sha>/index/`, the snapshot's git blob ids from
`git ls-tree`, the revision SHA, and reuse sources (the working-tree cache
keyed by the attached root, and every other indexed revision directory).

`index-metadata.json` is now **format 3**: each `StrategyRecord` carries a
`contentDigest` (SHA-256 over `path\0blob\n` for every file under the
strategy's project directory plus build files in its ancestors;
`ContentDigest`) and, when the file was copied rather than generated, a
`reusedFrom` label. Working-tree runs hash their files once per generation
to record the same digest. Format-2 records have no digest and are never
reused; they still serve their own repository as before.

Freshness for a snapshot compares digests per strategy (the mtime fingerprint
is ignored); a working tree keeps the coarse fingerprint. Before a tool runs
for a strategy, the service looks for a record with the same strategy id and
digest in each reuse source, copies that `.scip` into the revision's cache,
and reports the outcome as **Reused from <label> (identical bytes)**. All
reused or all generated is Current; a mixed run is **Partial** because
references from a reused project into a regenerated one may be outdated.
Document-level surgery on a merged index is deliberately not attempted:
`SemanticIndex` normalizes symbols and references across inputs, so the unit
of replacement is a strategy file. The Before revision is never indexed and
no index is mapped onto Before bytes (`SemanticAvailability.revisionNotIndexed`).

## Same-file occurrence selection

An unmodified primary click asks the mapped `DocumentSemantics` for the
occurrence at that canonical byte and uses the normalized `SemanticSymbolID` as
the join key when SCIP fully covers that identifier in its function. Every
nonempty occurrence of that identity in the active SCIP document is returned,
including definitions and external symbols whose definition is outside the
repository.

SCIP can legitimately omit host-inactive source, such as Rust guarded by
`#[cfg(target_os = "android")]`. For reader highlighting only, Radiology falls
back to Tree-sitter's innermost function/closure scope and exact identifier-token
spelling when the semantic occurrence set does not cover the parsed local set.
This intentionally includes a parameter and a same-named shadowing local, as
requested, while excluding comments, strings, keywords, numbers, and other
functions. The fallback is explicitly syntactic: it has no symbol identity and
is never used by Cmd-click, Go to Definition, Find References, or history.

The semantic model owns this persistent, document-scoped selection and clears it
on whitespace, file or repository replacement, and index replacement. Ranges
remain UTF-8 bytes until `SourceViewer` converts them through `SourceBuffer` at
the TextKit boundary. `ReaderTextView` paints them in `drawBackground`: passive
occurrences receive a subtle dynamic accent fill and the active occurrence a
stronger fill and stroke. It does not add or remove text-storage or temporary
layout attributes, so hover underlines, Find, destination feedback, selection,
copying, and the immutable source remain separate owners.

Folded/null glyphs are omitted by splitting each occurrence into currently shown
glyph runs before enumerating rectangles. Thus hidden occurrences do not stack
onto a fold line; revealing a fold displays them without recomputing or guessing
coordinates. Ordinary clicks do not navigate, modify history, or unfold code.
Cmd-click retains definition navigation. Native drag selection continues through
`NSTextView` unchanged; both a single caret click and a double-click word
selection refresh occurrence decoration after AppKit updates the selection.

An unmodified double-click also toggles a locked occurrence group, using the
same semantic-first, function-local-fallback resolution described above. Native
word selection still happens normally. Locked groups are drawing-only and
document scoped: they survive transient selection, whitespace clicks, folding,
font and appearance changes, and leaving and revisiting the file during the
repository session. Multiple groups may be locked. Double-clicking any member
of an existing group removes only that group and clears the transient wash
created by the first click of the sequence. Command-modified clicks never pin.

The pin store keys each document by repository-relative path plus a byte-count
and content checksum. Changed bytes therefore invalidate stale coordinates,
while index or syntax replacement over identical bytes preserves valid pins.
Semantic identity is preferred; identical range sets reconcile a syntactic pin
with semantic data that arrives later. Color slots increase monotonically for
the session, so removing a group never recolors surviving groups. The palette
cycles rather than imposing a pin limit.
