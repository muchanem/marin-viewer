# Rust trait implementations

Implemented 2026-10-11 after the user authorized the proposal and asked to
precompute implementations during indexing where useful. The historical
assessment below is superseded by this delivered contract.

## Dense pane refinement (2026-10-11)

The user superseded the expanded presentation: the caption is now **Trait
Implementations** with a compact block count. There is no separate trait-name/
Trait subheading, file-section heading, disclosure triangle, source expansion
or routine coverage footer. The pane is a flat native plain list with 22-point
rows: primary callout monospace semibold implementing type and secondary
caption file:line on the same row. Full path/signature and trait/coverage context
remain in help/accessibility. A partial-coverage icon appears only for gaps.

Every full row is a native plain Button. A single click invokes
`AppModel.openTraitImplementation`, selects the row and commits the existing
byte-verified navigation; Back retains the exact departure caret. ↑/↓ selects,
Return activates, Escape clears. The preview view, worker preview method,
disclosure state and preview tasks were removed. Index generation/cache,
snapshot identity, freshness and pane preferences remain unchanged. The checked
pane menu uses the same Trait Implementations label without changing its saved
preference key.

The existing real-index/navigation test now exercises the primary row action,
native three-row-only list structure and row height ≤24 points, alongside exact
Back/cache reload. Updated tests retain trait/member selection, index/Before
clearing, pane toggles, negative impls and changed-source rejection. Six actual
production pane renders at220/280/420 points in light/dark were inspected under
`/tmp/radiology-dense-trait-renders/`. The newest PROGRESS.md records final gates.
Physical clicks in the shared reader were not performed; attempted synthetic
application mouse events prematurely ended the test-runner lifecycle and were
removed rather than presented as a completed test.

## Earlier delivered behavior (UI superseded above; indexing still current)

The existing middle Context pane becomes **Implementations** while the caret
is on a Rust trait name, inside its declaration (including requirements/default
methods), or inside an explicit impl of that trait. References remain above and
Bookmarks below; the existing two native dividers resize the three independently
scrolling panes. Other contexts retain Definition/Outline. No extra permanent
split or toolbar control was added.

Rows group by file and show the implementing type prominently, with line
numbers and disclosure. Full impl signatures remain in help and real-source
previews. ↑/↓ selects, →/← expands/collapses, Return/double-click or the context
menu opens the impl, and Escape clears selection. Selection/disclosure do not
move source. Back restores the exact departure caret even after scrolling.
Blanket impls appear once with source constraints; negative impls are marked
and counted separately from positive implementations.

`RustTraitImplSyntax` extracts actual Tree-sitter impl nodes and the implemented
trait's terminal name token, peeling generic types and qualified paths.
Bounds, type arguments, inherent impls, comments and unexpanded macro token
trees cannot create impl results. A lightweight `SyntaxWorker.rustTraitImpls`
indexing pass omits highlights/folds/calls/outline. Normal parsing also includes
these ranges in open-file snapshots for context selection.

`TraitImplementationIndexer` resolves each header token to exactly one distinct
nonlocal, nondefinition SCIP identity at the token's exact byte range. Missing
or ambiguous identities count as unresolved. It never joins traits by spelling.
Repeated SCIP contributions do not duplicate source blocks.

`SemanticIndexService.emit` precomputes the lookup before publishing changed
semantic maps, attaching `TraitImplementationIndex` to the immutable index.
The main actor does no repository parsing when the reader browses traits.
`rust-trait-implementations.json` lives in the repository/revision cache outside
the viewed repository. Format/extractor version 1 keys each file by the exact
Git-style source blob hash plus a SHA-256 digest of semantic identities, roles,
coordinates and encoding. Warm loads verify bytes/semantic data without
reparsing. Missing/corrupt/old derived caches rebuild automatically; write
failures affect performance only. Existing SCIP caches need no Cargo rerun
merely to gain the derived lookup.

Untrusted loaded contributions (stale cached or failed/pending outcomes) are
excluded. PR snapshot blob IDs additionally verify file bytes. Cancellation
and a post-enrichment generation guard prevent cross-repository publication.
`TraitImplementationWorker` verifies each full destination blob before preview
or activation, rejecting even same-length edits. Navigation checks repository
generation, index revision and current row identity. Errors preserve history.

`ContextModel` owns a separate main-actor observable `TraitImplementationsModel`.
Grouping/sorting happens on context changes; preview actors/tasks stay outside
view bodies. Caret movement within a trait/member preserves selection and
disclosure. Trait/repository/index changes clear state and reject late work.
Before has no mapped semantics, so it acquires no After implementation context;
semantic PR destinations use After through the existing navigation path.

## Coverage, design and evidence

This lists explicit semantically indexed source impls. Macro/derive expansions
and cfg-inactive source may be absent; current Rust indexing disables build
scripts and proc macros. Coverage reports unresolved headers, unindexed Rust
files, stale contributions, read failures and parse errors. Empty lists say
**No indexed implementations**. A blanket declaration is not an enumeration
of every concrete type it could apply to.

SwiftUI before/after review used data-flow, performance and view guidance;
macOS layout/interaction guidance informed the existing middle-pane design.
Typography reuses caption semibold headings, title3 semibold distinct-trait
titles, callout monospace semibold implementing types, regular callout monospace
source, and caption regular/tabular metadata. Primary/secondary system text and
a faint dynamic indigo cue work in both appearances.

Fresh full suite: **288 tests /62 suites**. A checked-in real rust-analyzer 1.97.1
fixture tests alias/path/blanket/negative identity, bounds/macro exclusion and
duplicate contributions. Additional tests cover persisted reload and source/
semantic invalidation, corrupt caches, stale inputs/failed regeneration,
missing/unresolved source, same-length edits, trait/member/impl context,
selection/cancellation/index replacement, Before isolation, passive previews,
service precomputation, exact navigation/Back, and native divider movement in
both directions. Production rows at 220/280/420 points in light/dark were rendered
and inspected. Physical shared-reader interaction/restart was not performed.

Read-only probe against the existing app-owned tkos cache: **348 documents,
78 trait identities, 585 impl blocks, 3 unresolved headers**, zero read/parse
failures. Cold enrichment **2.639 s**; a fresh-actor warm load **0.413 s**, with
**348 cache hits and zero reparses**. Derived data went to disposable `/tmp`
storage, leaving the repository and original cache untouched. Run with
`RADIOLOGY_TRAIT_PROBE=<cache directory> swift test --filter TraitImplementationRealDataProbe`.

Logs: `/tmp/radiology-trait-{tests,check,build,probe}.log`; renders:
`/tmp/radiology-trait-renders/`. The newest PROGRESS.md records build/signing/
resource gates. Relaunch the app to load this code; existing SCIP data is
enriched automatically on open.

## Historical feasibility assessment (before authorization)

The following records the earlier estimate and alternatives, not current scope.

## Assessment

A useful first version is a small-to-medium addition: roughly 1–3 focused
engineering days including meaningful tests and native inspector validation.
This is an estimate from the existing architecture, not a measured schedule.
The inspector, semantic identities, reference lookup, source parsing, preview,
and exact-location navigation already exist. The main new work is recognizing
which references actually identify an implemented trait.

Radiology uses batch `rust-analyzer scip`, not a running language server.
The current upstream [SCIP emitter](https://github.com/rust-lang/rust-analyzer/blob/master/crates/rust-analyzer/src/cli/scip.rs)
constructs symbol records with empty relationships. This agrees with the
2026-10-04 real-index measurement in [critical-lens.md](critical-lens.md): zero
relationships across 56,389 symbol records. The decoder already understands
`isImplementation`, but Rust provides no such edges to reverse here.

Rust-analyzer's [Go to Implementation](https://github.com/rust-lang/rust-analyzer/blob/master/crates/ide/src/goto_implementation.rs)
already resolves traits and enumerates their impls through its semantic
database. Using that capability through LSP is an alternative requiring a new
server lifecycle, workspace/configuration management, and snapshot coordination.
It is a larger addition than extending the current batch-index architecture.

## Recommended first slice

1. Resolve the trait to its exact `SemanticSymbolID`.
2. Read `SemanticIndex.references[traitID]`, grouping candidate positions by
   file so only candidate files need loading and parsing.
3. Extend Rust syntax extraction to expose an `impl_item`'s implemented trait
   name token, target type, generic constraints, polarity, and block range.
   Current `symbols.scm` captures the target `type`, not the `trait` field.
4. Accept a block only when the implemented trait's name token resolves to
   the requested identity. Mere containment within an impl is insufficient:
   trait references in bounds, type arguments, or method bodies are not impls
   of that trait. Validate real SCIP header occurrences before UI work.
5. Deduplicate by snapshot/path/block location. Show one row per explicit impl,
   including generic/blanket impls with their source constraints. A blanket
   impl is one declaration, not an enumeration of every applicable type.
6. Load asynchronously and cache against repository/snapshot, index revision,
   trait identity, and source freshness. Reuse Context cancellation/generation
   guards and canonical UTF-8 locations.

Exact identity should support aliases, qualified paths, and same-named traits
in different modules; those need fixture and real-index verification. Negative
impls must be distinguished from positive implementations.

## UI fit

An **Implementations** region in the existing right Context inspector can
follow the trait being examined. Reuse the current native list and concise
rows, source disclosure, preview selection, Return/double-click commit, and
exact Back history. Keep References available. Decide placement and resizing
with the actual three-pane inspector before adding another permanent split.
No new toolbar control or typography scale is needed for this proposal.

The architecture was checked before and after the recommendation against
`swiftui-pro` data-flow, view, and performance guidance: use a main-actor
observable model, a separate query actor, stable row identities, and no disk
work or repeated filtering in view bodies. `macos-design` layout/interaction
guidance favors contextual presentation and the existing keyboard behaviors.

## Meaning of “every” and validation

This first slice finds explicit, semantically indexed source impl blocks.
Generated macro/derive impls, cfg-inactive source, unindexed crates, and stale
or partial semantic coverage prevent a claim of repository-wide completeness.
Current Rust indexing explicitly disables build scripts and proc macros.
Label coverage honestly; “No indexed implementations” is safer than implying
that no implementation exists. Before PR source currently has no semantics.

Broader macro support can use rust-analyzer's implementation query, but its
answers still depend on the loaded workspace and active configuration. No
single configuration proves coverage across every feature/target combination.

Meaningful acceptance cases: duplicate trait names, imported aliases,
qualified/generic trait paths, blanket and negative impls, bounds-only uses,
ordinary/inherent impls, parse/read failures, rapid caret or repository changes,
partial coverage, source freshness, PR revisions, and exact navigation/Back.
No code changed and no fresh build or tests were run for this assessment.
