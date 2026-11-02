# Future-agent handoff

## Reading order and workspace status

**2026-10-31 publication batch:** all nonignored local changes are bundled for
direct publication on GitHub `main`, as explicitly requested by the user.
The starting branch and local/remote `main` shared `6d446b9`, so this uses a
normal fast-forward push without a PR merge. Read PLAN.md and the newest
PROGRESS.md first for the current Code Paths/sidebar behavior and validation;
the local/uncommitted descriptions below are historical.
[Publication details](github-publication.md).

Latest C/C++ decision: the user explicitly requested best effort without build
information. scip-clang now automatically indexes original source using a
temporary GNU C11/C++20 database with inferred include paths, always persisting
Best effort/Partial coverage. Real databases take priority and regenerate on
arrival/removal. No configured build is required. Cancellable preparation and
memoized header discovery keep repository switching responsive. Read
[clang-best-effort.md](clang-best-effort.md) and newest PROGRESS.md for gates
and actual tkfiasco coverage; this supersedes the prerequisite below.
Actual tkfiasco index: 15,669 documents/523,683 symbols/2,820,466 occurrences,
normal app cache primed and verified; thread.cpp 467 occurrences map exactly.
Cold 321.438 s/warm 18.144 s, no source writes. **305 tests /67 suites**, final
targeted 8, check/build/strict signing/resources pass; signed 17:56:17 CDT.
Relaunch the upgraded app to use the cached index.

C/C++ work (2026-10-13): official C/C++ grammars and five query roles,
recursive declarator names, `.h` mixed headers and `.C` routing; scip-clang
managed Apple Silicon install with pinned SHA-256, build database discovery,
temporary logs and persisted partial coverage. The tool is installed here.
tkfiasco benefits from real build inputs and uses custom Fiasco preprocessing;
upstream extern-C omissions remain unavailable. **301 tests /66 suites**,
check/build/strict signing and empty-env packaged resources (10 grammars,
47 queries,4 scripts) pass. Relaunch the built app for the registry. Read
[c-cpp-support.md](c-cpp-support.md) and newest PROGRESS.md for final gates.
Prior uncommitted reader work is retained; no push/merge or shared app restart.

Latest refinement (2026-10-11): dense **Trait Implementations** caption/count,
flat 22-point type/file:line rows and single-click navigation with exact Back.
Separate trait/file headings and all implementation disclosure/preview UI,
state/tasks and worker preview code removed. Native plain Buttons retain full
path/signature help, keyboard selection/Return, negative markers, and coverage
help/gap icon. Same index cache and pane preference key. **291 tests /63 suites
pass with --no-parallel**; row structure/height and primary action/Back checked,
six actual pane renders inspected. Read [rust-trait-implementations.md](rust-trait-implementations.md)
and newest PROGRESS.md for build/sign/resource evidence. Previous reader work
retained on codex/toggle-current-function; user reader not restarted.

Latest local work (2026-10-11): persistent checked Panes and View > Context
Panes menus control References, Definition/Outline, Implementations and
Bookmarks. The contextual middle slot has a definition fallback; all-off
recovery stays reachable. Active native split regions reflow while model
selection/disclosure/bookmark and source/history state survive. All 16 choices,
native lists/dividers and 12 light/dark renders verified. **291 tests /63 suites
pass with swift test --no-parallel**, check/build/sign/resources pass; signed
**16:39:26 CDT**. Parallel full runs expose the Files manual-scroll timing
assertion, while Files alone and with pane tests pass. Read
[inspector-pane-controls.md](inspector-pane-controls.md) and newest PROGRESS.md
for gates and physical interaction limits. Earlier reader work is retained,
local/uncommitted on codex/toggle-current-function.

Latest local feature (2026-10-11): Rust trait contexts show Implementations in
the middle inspector pane. Impl blocks are resolved by exact SCIP identities,
precomputed before semantic publication, and persisted by source/semantic
digests; activation rejects changed bytes. Aliases/blankets/negative impls,
coverage and exact Back are tested; macros/configuration gaps remain explicit.
**288 tests /62 suites** pass. Read-only probe: 348 files, 585 blocks,
cold 2.639 s/warm 0.413 s, zero warm reparses. Existing x-key/Files work retained;
local/uncommitted on codex/toggle-current-function. Read
[rust-trait-implementations.md](rust-trait-implementations.md) and newest
PROGRESS.md for build/sign/resource evidence and physical UI limits.

Latest local work (2026-10-11): Files expands/selects/centers the current source
after navigation and returning from Search, including bookmark/same-file jumps.
View-only active-file exceptions retain filter settings and Before-only paths;
sync preserves exact caret/history/revision. Actual native List/scroll tests pass;
**277 tests /59 suites**, check/build/sign/resources, signed **15:37:26 CDT**.
Local with x-key changes on codex/toggle-current-function, not published. Read
[files-sidebar-navigation.md](files-sidebar-navigation.md).

Latest local work (2026-10-11): plain x in the focused source toggles the current
named function's own fold, with nested/default-lambda ownership, ancestor reveal
and unchanged canonical selection/source/history. Unmodified, non-editable,
non-composition route only; repeat events are consumed. **273 tests /58 suites**
pass, including native keyDown/TextKit and seven grammar probes. On local branch
codex/toggle-current-function after the earlier publication below. Read
[function-fold-key.md](function-fold-key.md) and the newest PROGRESS.md gates.

**Current publication state (2026-10-11):** all accumulated workspace source,
tests, assets and docs are committed and merged to GitHub main through
[PR #1](https://github.com/tqbf/radiology/pull/1), feature commit3b8f7f5 / merge
dfc877a at14:53:25 CDT. The user explicitly authorized this merge, overriding the
earlier restriction for this batch. Local main was fast-forwarded to the confirmed
remote merge; publication metadata follows in a documentation commit. Start new
work from main. Earlier local/uncommitted descriptions below are historical.
269-test/signed-build validation remains the latest implementation gate; physical
UI limits still apply. See [github-publication.md](github-publication.md).

Latest feature (2026-10-11): third resizable Bookmarks pane, ⌘D caret toggle,
ordered ⌘0…⌘9 slots, native drag and context-menu reorder, per canonical attached
checkout/PR-number preferences, explicit Before/After and exact Back. Persisted
anchors relocate unique unchanged source lines; errors leave the reader intact.
Normal/Critical shortcuts moved to ⌥⌘1/⌥⌘2. Two nested native splits pass both
divider tests (the flat three-child prototype failed the second divider).
**269 tests /57 suites**, light/dark renders and check/build/sign/resources pass;
signed **14:41:15 CDT**. Physical drag/menu/keyboard checks remain unverified;
desktop automation is unavailable. Read [bookmarks.md](bookmarks.md).
Changes local/uncommitted; user reader not restarted, no tkos writes or merges.

Latest caller refinement (2026-10-11): caller buttons are capsule pills with
12 dynamic colors selected by stable FNV-1a method-name/full-relative-file hash.
Matching pairs keep colors across branches and relaunches. Recursive caller
identities/declarations are cut before rendering a duplicate, with a preceding
branch-stop note. Separate same-named functions and unrelated branches remain.
**263 tests /55 suites**, narrow light/dark renders, check/build/strict signing/
packaged resources pass; built **13:47:46 CDT**. Automation retry lacks @oai/sky
in this session, so no mouse checks or reader restart. Read
[caller-pills.md](caller-pills.md); workspace remains local/uncommitted.

Latest inspector work (2026-10-11): expanded references include incoming caller
trees from the containing callable, with exact SCIP/parsed-site edges, preserved
branches, recursion and explicit unknown boundaries. Initial 256-row budgets
continue on demand without a depth cutoff. Native VSplitView restores a movable
References/Definition divider and independent scrolling, superseding the outer
scrolling layout below. **260 tests / 54 suites** pass, including native divider
resizing, a 270-level tree, and exact-caret caller/Back navigation. Three-width
light/dark renders pass; physical UI unverified because Sky could not start.
Read [reference-call-trees.md](reference-call-trees.md). Changes remain local.

Latest inspector pass (2026-10-08): strong title3 semibold symbol/kind/file:line,
caption References/Definition headers, top-stacked content replacing VSplitView,
bounded native list budgets, primary code text and faint system-color section
backgrounds (2.5% light/5.5% dark). Exact SCIP identity suppresses repeated
Definition name; different target remains named. Native PR758 dedup/disclosure/
Return/Back and three-width light/dark renders pass; different-target live case
unverified. **253 tests / 52 suites** after existing highlight timing failure,
targeted pass and unchanged full rerun; check/build/sign/resources pass. Built
**22:59:05 CDT**. Review app closed, user reader preserved. Read
inspector-refinement.md; it supersedes earlier fixed vertical-split descriptions.

Latest UI pass (2026-10-08): toolbar mode is a selected-value dropdown (Normal
default) beside Before/After; filters are View-menu-only with Show All Files.
Sidebar modes are tab buttons with no Browse caption, selected underline and
verified keyboard Files→Search. Changes rows retain two lines with stronger
filename, caption path/counts, tabular right lane, M/plus statuses and selected
tint/marker. Summary spacing improved; footer names Source only/Tests hidden,
head SHA in tooltip. Native PR758 and three-width light/dark renders pass.
**253 tests / 52 suites**, check/build/sign/resources pass; built **17:35:01 CDT**.
Review app closed, user's reader preserved. Read sidebar-refinement.md; it
supersedes older toolbar/filter/revision layout descriptions below.

Latest source-header refinement (2026-10-08): fixed194-point trailing revision/
change group (136-point picker), hidden visible Revision label, adaptive leading
breadcrumb. Flat uniquely identified ViewThatFits alternatives retain nearby
directories and declaration ancestors one at a time; file/final name take
priority in tight space. Full path/all declaration jumps remain in ellipsis.
Live PR758 line150 now shows crates/harness-core/src/nomex.rs/Nomex/admit_call;
Before/After/menu and five-width light/dark renders pass. **253 tests / 52
suites**, compile/build/sign/resources pass; built **17:02:10 CDT**. Review app
closed, user's reader preserved. Read [source-breadcrumbs.md](source-breadcrumbs.md)
for IDs, type hierarchy and actual acceptance evidence.

Latest lifecycle feature (2026-10-08): normal relaunch restores the last attached
repository/confirmed PR through fresh metadata. Exit PR saves local checkout;
CLI/manual choices win and failures preserve the saved PR. See
[session-restoration.md](session-restoration.md) for persistence/task guards and
native separate-instance quit/relaunch of tkos #758. Seeded the real app's
current tkos #758 record for its first upgraded launch; user's process untouched.
**253 tests / 52 suites**, compile/build/sign/resources pass; built **16:36:48
CDT**. Review app closed; workspace remains local/uncommitted.

Latest UI refinement (2026-10-08): grouped detail-scoped native toolbar,
repo Open menu, labeled PR/compact refresh/Exit menu, modes/filter/search/Context.
Live isolated review verified menu actions, shared filter state, left-sidebar
button/Ctrl-Cmd-S, and Exit PR. Gutter is now72 points/20-point hit lane and
shows fifth canonical lines plus native caret only; fixed small11pt UI numbers,
current medium/primary. Native draw/fold/scroll tests and live caret7→8 pass.
**246 tests / 51 suites**, compile/build/sign/resources pass; signed **16:10:23
CDT**. Native narrow resize/dark/count-edge cases remain unverified; review-only
process closed, user's reader preserved. Read toolbar-layout.md/source-gutter.md.

Latest repair (2026-10-08): the actual app's workspace copier mishandled tracked
directory symlinks and dangling AGENTS.md, and omitted tracked vendor inputs.
Links now rebase/hash as links; full build inventories feed copying and cache
proof. The real PR758 SemanticIndexService path passes: 2,088 source documents,
18 refs/4 files, generated/partialBuild, cache/cleanup verified. **244 tests / 50
suites**, check/build/sign/resources pass; signed **01:10:35 CDT**. No physical
UI restart/check. See newest PROGRESS.md and kotlin-semantic-indexing.md.

Latest slice: Kotlin semantic indexing (2026-10-07), **241 tests / 50 suites**,
signed **18:36:00 PDT**, compile/build/strict signing/resources pass. Real PR758
Contacts addSecrecyTag resolves to SecrecyCtx.kt:18, 18 refs/4 files, broader 2,379
compiler documents with honest Partial native-setup failures. Managed tool is
installed; new registry requires relaunch. No physical UI acceptance claimed.
Read plans/kotlin-semantic-indexing.md for source pin/AGP9 attachment, isolation,
pre/post input proof, generated-document boundary, UTF-16 defaults and cache/
reuse invariants. Native-component PR caret/reference/definition/Back tests pass.
The preceding Context recovery adds View Show/Hide + Opt-Cmd-I; physical drag
acceptance remains manual. Earlier baseline statements below are historical.

Read `README.md`, `PLAN.md`, the top of `PROGRESS.md`, this file, and `plans/development-history.md`, then the subsystem document for the requested task. For Critical Lens work read `plans/critical-lens.md` first: it records which SCIP facts actually exist (no relationships from rust-analyzer; enclosing ranges on definitions) and the stage-two call-graph rules (closure/nested-function sites are conditional nodes, never direct edges; known-zero is distinct from no-body/partial). The user earlier confirmed the large-function folding fix. Newer requests delivered the caret-driven Context inspector, source Return/Enter navigation, a compact default with one line per reference/definition and explicit disclosure, a subtle visible source caret (`plans/context-sidebar.md`), and a faint background under the current named function (`plans/structural-navigation.md`). Opus 5.5 implemented them; GPT Sol verified the caret and function-shading builds live on tkos (`plans/context-ui-review.md`), including concise default rows and the Definition heading. Full disclosure/narrow-width acceptance and the old README availability-label screenshot remain manual. There is no heartbeat.

The root SwiftPM package is the only active codebase, now tracked in Git on `main` for [tqbf/radiology](https://github.com/tqbf/radiology). The user explicitly authorized Git initialization, committing the project, and publishing it after the documentation round. Any local nested `repo/` is an inactive starter copy, ignored by Git; never edit it. Preserve unrelated workspace changes. Commits and PRs are allowed within the requested task, but agents must never merge to `main`.

## Architecture map

Radiology is a read-only repository browser, not an editor or LSP client.

| Area | Key entry points | Contract |
| --- | --- | --- |
| App/state | `RadiologyApp.swift`, `AppModel.swift`, `AppModel+Semantics.swift` | Main-actor orchestration; generation guards prevent stale async publication |
| Repository | `RepositoryWorker.swift`, `RepositorySnapshot.swift`, `CommandRunner.swift` | Git-aware discovery with filesystem fallback; browsing survives tool failure |
| Source | `SourceBuffer.swift`, `SourceStore.swift`, `ReaderTextView.swift`, `SourceViewerCoordinator.swift` | Immutable canonical UTF-8 bytes; UTF-16 only at TextKit boundaries; 16 MiB limit |
| Structure | `SourceLanguage.swift`, `SyntaxWorker.swift`, `SyntaxSnapshot.swift`, `Queries/` | Actor-isolated Tree-sitter; source publishes before parsing; malformed/unsupported files remain readable |
| Sidebar outline | `UI/DocumentOutline.swift`, `DocumentOutlineView.swift`, `OutlineRow.swift` | Flat callables first, descending half-open signature-to-end line span, source-order ties; original IDs/ranges; residual non-callable hierarchy without duplicates; path/content/symbol-keyed cache; one-line names and quiet metadata tabular counts; identical Normal/Critical |
| Navigation/folds | `NavigationHistory.swift`, `DocumentOutlineView.swift`, `SourceBreadcrumbs.swift`, `LineNumberGutter.swift` | Exact pinned destinations; passive scrolling does not add history; reveal removes enclosing folds |
| Search | `SearchWorker.swift`, `RepositorySearchView.swift` | Cancellable ripgrep process; optional dependency |
| File picker | `QuickFileSearch.swift`, `QuickFilePicker.swift` | Off-main cancellable fuzzy ranking; max 100 shown with truthful total |
| Semantics | `SemanticIndexService.swift`, `SemanticIndex.swift`, `SCIP/`, `Indexers/` | App-owned batch SCIP, normalized model, cached stale data, independent strategy outcomes |
| Context inspector | `Context/ContextModel.swift`, `DeclarationContext.swift`, `UnderCaretContext.swift`, `UI/ContextInspectorView.swift` | Identity-keyed regions; genuine caret (`caretLocation`) distinct from viewport `positions`; passive context never navigates; sidebar commits record the caret for Back |
| Occurrences | `DocumentSemantics.swift`, `OccurrencePinning.swift`, `ReaderTextView.swift` | Semantic identity first; local syntax fallback is drawing-only; pins are document/source-identity scoped |
| Critical Lens | `Critical/CriticalityPolicy.swift`, `CriticalLensModel.swift`, `SourceProjection.swift`, `SourceViewerCoordinator.swift` (draw hook), `AppModel+CriticalLens.swift` | Classification by SCIP identity/package with explicit precedence; projection bound to exact source identity; draw-time opacity only, no storage/layout change; marks persisted per repository under Application Support; see plans/critical-lens.md |
| Pull request review | `PullRequest/GitHubClient.swift` (gh, timeouts), `ReviewRepository.swift` (bare repo + alternates, fetch by SHA, worktrees, Before blobs), `UnifiedDiff.swift`, `FileChange.swift`, `PullRequestModel.swift`, `AppModel+PullRequests.swift`, `UI/PullRequestMenu.swift`, `PullRequestNumberSheet.swift`, `ReviewChangesView.swift` | `attachedRoot` is the identity for gh, marks and the working-tree cache; `repository` is the head worktree while reviewing. `SourceLocation.revision`/`SourceBuffer.revision` separate Before and After documents; `positions`/pins key by `positionKey`; history resets on entering/leaving a review. Before reads come from `revisions/<base>/files`; Before gets `semantics.bufferChanged(nil)`. Semantic destinations force `.after`. Index options: flat revision cache, blob ids, reuse sources (`IndexReuseTests`). See plans/pull-request-review.md and plans/pull-request-ui-review.md; conservative whole-repository digest until dependency graphs modeled, mixed provenance remains Partial on cache reload, blob-to-blob hunks |
| Source filters | `Repository/SourceFilters.swift`, `TestPathClassifier.swift`, `SourceFileClassifier.swift`, `AppModel+SourceFilters.swift`, `Syntax/TestDetection/` (detector + per-language extensions, `RustCfgPredicate`), `Source/TestCodePresentation.swift`, coordinator/gutter/reader hooks, `UI/RepositoryFilesView.swift`, `SourceFilterToggles.swift`, `FileTreeRow.swift`, `FileTreeExpansion.swift`, `TestCodeStatusView.swift` | Two independent persisted options (Hide Tests ⌃⌘T, Source Files Only ⌃⌘O). Files tree/query and PR Changes use shared path policy (⌘K/Search/indexing unfiltered); deleted Before path, rename either available path; visible counts/totals and selection sync without navigation; repository model never filtered; open file never closed. Test regions come from parsed node shapes (`SyntaxSnapshot.testRegions`, `isTestOnlyDocument`) and are hidden through the fold union with a dimmed header; `revealedTestRegions` is per loaded document; explicit navigation reveals (pending until syntax arrives); test documents shown in full. See plans/source-filters.md |
| Call graph / summaries | `Queries/*/calls.scm`, `Syntax/SyntaxSnapshot+Calls.swift`, `Critical/CallGraph.swift`, `CriticalFrontierBuilder.swift`, `CallGraphWorker.swift`, `CriticalSummaryModel.swift`, `UI/CriticalHoverView.swift`, `UI/HoverDestinationRow.swift`, `Source/HoverPopoverHost.swift` | Edges only from parsed sites resolved to SCIP occurrences; lexical ownership, bounded BFS, via paths and honest coverage; worker epochs prevent stale cache writes. Only source hover and fold-gutter work remain: no sidebar summaries, outline counts, critical-list row dispatch, or caret-triggered summary requests. Hover destinations use full-row buttons; a stable host, native tracking and pointer transit retention keep loading updates and pointer entry from replacing the popup. Gutter receives generic `CountAnnotation` values |

## Invariants and pitfalls

1. **Bytes are canonical.** Tree-sitter and app navigation use UTF-8 byte offsets. SCIP UTF-8/16/32 positions are converted against the loaded `SourceBuffer`. TextKit uses UTF-16 only at its boundary. Test emoji/non-ASCII whenever ranges change.
2. **Browsing never waits for analysis.** Publish source immediately; syntax and semantics arrive asynchronously with cancellation and generation/repository guards.
3. **Semantic actions never guess.** The cfg-inactive exact-identifier fallback may decorate same-spelled tokens inside one function/closure, including shadowed locals, but may not supply definition/reference targets.
4. **Folding does not alter backing text.** Null glyphs/zero advancement hide effective disjoint outer folds. The gutter enumerates actual visible TextKit fragments. Preserve original line numbers, copy/find ranges, pins, history, and canonical bytes.
5. **Fold performance is range-indexed.** Effective ranges are sorted/disjoint, membership is binary search, and updates diff old/new unions. Avoid whole-document glyph regeneration and per-character linear fold scans.
6. **Reveal before scroll.** Outline/semantic/history targets must unfold all hiding ancestors, force the necessary layout, then reveal with revision guards. Passive synchronization must not overwrite committed history.
7. **Indexer failures are isolated.** Successful strategy output survives another strategy's failure. Degraded Rust output remains Partial. Diagnostics retain bounded head and tail so the first Cargo error is not lost.
8. **Repositories are never modified for indexing.** Use real manifests/features/cfg identity. Do not vendor tkos or create synthetic shadow manifests.
9. **Pins have stable identity/color.** Key them by document plus source byte count/checksum and canonical ranges; changed content invalidates them. Removing a group must not recolor remaining groups.
11. **Revisions are documents.** In a review the same path names a Before and an After document. Never compare locations by path alone (`sameDocument`), never map the After index onto Before bytes, and never reuse a strategy index without a matching format-3 content digest.
12. **Test hiding is a projection.** Hidden test ranges join the fold union in `SourceViewerCoordinator.applyFoldAttributes` (sorted, disjoint, merged); never alter storage, Tree-sitter or SCIP input. Fold IDs are independent of test reveal state, so toggling Hide Tests preserves folds. A `TestCodePresentation` applies only to its exact path + content identity.
10. **Caret is not viewport.** `positions` mixes caret and scroll top for restoration only. Context, Go to Definition/Find References at caret, and all sidebar commits use `currentCaretLocation` (the genuine caret). Context updates must write observable state only on identity change.

## Current implementation facts

- Syntax: Swift, Rust, Go, Python, JavaScript/JSX, TypeScript/TSX, Kotlin; eight grammar registrations and 37 Radiology `.scm` resources.
- Semantics: adapters for Rust, Go, TypeScript/JavaScript, Python, C/C++, and Kotlin/Java Gradle. Kotlin compiler support is validated on Kotlin2.4.20/AGP9.4.1/Gradle9.7.1; see kotlin-semantic-indexing.md. No Swift adapter. C/C++ requires `compile_commands.json` and manual `scip-clang`; Python needs 3.10+.
- Cache: `~/Library/Caches/Radiology/repositories/<repo-id>/`. Provisioned tools/support: `~/Library/Application Support/Radiology/tools/`.
- Gutter: 72 points; 20-point disclosure lane; fifth canonical lines plus native caret (11pt metadata), 3-point logarithmic 6–16-point meter; 9-point count badge when space permits, exact tooltip/accessibility otherwise. See source-gutter.md.
- Latest recorded baseline: **234 tests/47 suites** (3 opt-in tkos probes skip by default), signed build **2026-10-06 20:52:31 PDT**, after active PR refresh. Visible Refresh PR + single Cmd-R context route fetch latest metadata/head/base; old reader protected/usable until fallible listing/source mapping prepares, then atomic swap. Same head+base metadata-only. Latest/pending reader restored via byte proof/Git hunks; worktree leases, refresh-intent retry/cancel/stale guards tested. Snapshot change clears SHA-old history; only current-file byte-proven pins remain, options preserved, Before syntax-only. No live UI/remote refresh; see pull-request-ui-review.md. Preceding changed-fold baseline was 227/46 signed 14:47:45. ReviewFoldInput + FoldHeaderOwnership and coordinator lifecycle select changed ranges/points/ancestors once both matched inputs arrive; manual choices/bulk commands win and old counters baseline on new coordinator. Hide Tests unchanged; late viewport restore cancels stale markers and newer navigation wins. Parser/native component tests pass; no UI attempt. See structural-navigation.md and pull-request-ui-review.md. Previous changed-block controls baseline was220/45 signed14:22:51. ChangeBlockNavigation plus shared directional availability governs compact up/down buttons and existing ⌥⌘↑/↓ menu bindings. Hunk skip-current/no-wrap, byte EOF anchors, genuine-caret Observation invalidation and exact Back departure are regression-tested. Native attachment/recovery selected old #753 reader; no UI actions/screenshots, manual checks in plans/pull-request-ui-review.md. Preceding shared-filter fix was 216/44 signed19:00:13 PDT. Changes applies both SourceFilters options; rename/copy either available path, deleted Before; visible counts/totals, filtered-empty reset and selection sync preserving reader/history/revision. Canonical review.changes remains full. No native attempt; prior visual limits persist. Preceding filter acceptance repairs were 213/43 signed23:23:22 CDT. pytest test_ prefix, production Vitest else preservation, hit-ID refresh and hidden-header glyph rejection have meaningful detector/AppKit regressions. Two targeted tkos probes rerun; native attachment/recovery selected old #691 reader, so UI work stopped without actions/screenshots. See plans/source-filters-ui-review.md for precise manual steps. The previous Opus baseline was 210/43 signed23:16:01. Check, test, swiftbuild bundle, strict deep codesign and empty-environment resources (8 grammars) pass. Real tkos probe (`RADIOLOGY_REAL_TEST_FILTER_PROBE=1`) matched app.rs 35–43 / 803–833 (834 production visible) / 3424–EOF. No UI was exercised; GPT Sol owns live acceptance in plans/source-filters-ui-review.md. The preceding baseline was **186 tests/39 suites**, signed build **2026-10-04 20:18:12 CDT**, after visible Exit PR affordance. Native titleAndIcon Exit PR appears beside the selector when active/loading, uses existing exit/cancel to local checkout and clears pending load errors; no branch switch. Cancellation regression preserves reader/history and suppresses late aborted error. No native UI attempt in this round. Previous PR acceptance repairs were signed 20:07:43. Conservative whole-repository/versioned digest context replaces project-local reuse; mixed provenance Partial survives reload/refresh, revision options persist, hunks use full pinned blobs and PR failure recovery is a native root alert. Real phone-provisioner After index generated one document (3,711 valid occurrences), matching reuse and simulated-context regeneration passed. PR native attempt/recovery selected the older shared reader: no UI actions/screenshots; see plans/pull-request-ui-review.md for exact manual checks. The preceding Fable baseline was 184/39 signed 19:56:31. Check, test, swiftbuild bundle, strict deep signing and empty-environment packaged resources pass. No UI was exercised in that round; see the newest PROGRESS.md entry for Sol's checklist and the real tkos read-only probe (`RADIOLOGY_REAL_PR_PROBE=1`). The preceding baseline was **169 tests/34 suites**, signed **17:35:04 CDT**, after function-first size-sorted outline. New tests cover flat nested methods/functions, source-line span ordering/ties, Unicode half-open ranges and identical-content path invalidation. Native outline check was stopped when attachment selected the old shared reader; no pointer action or new screenshot was made. The preceding hover interaction repair was gated at 166/33, signed 17:21:39. Check, test, swiftbuild bundle, strict deep signing and empty-environment packaged resources (eight grammars with calls queries) pass. Popup names and full rows are buttons for real indexed destinations, with native tracking and transit retention. Physical clicks remain unverified: both native attachment attempts selected the user's older reader; only the separate review process was closed, preserving the user's pins and marks. Relaunch the signed build before the manual hover/click/Back check. Source call focus, marks, hover and gutter counts remain; the sidebar is identical across modes. The preceding **163-test / 16:53:36** aggressive call-focused rendering was verified live in light mode and accepted by the user (“this is much better”); the sidebar removal was gated at 164/32. Hover navigation, folded-count semantics and dark mode retain their explicit unverified status. See `plans/critical-lens-ui-review.md`; never recreate removed sidebar depictions from historical plans. Treat these gates as historical for subsequent code changes until rerun.
- User acceptance: after the isolated benchmark and CUA attachment limitation, the user independently confirmed the folding fix works.

## Validation commands

Choose checks proportional to the change:

```sh
make check
make test
make build
codesign --verify --deep --strict "build/Marin Viewer.app"
"build/Marin Viewer.app/Contents/MacOS/Marin Viewer" --verify-resources
```

The opt-in real-source folding probe requires the external tkos checkout:

```sh
RADIOLOGY_REAL_FOLD_BENCHMARK=1 swift test --filter realAppFoldPerformanceProbe
```

Do not describe its timings as full-app pointer latency. For indexing, distinguish fixture generation, product-code lookup against a cache, and a controlled cold app run on untouched tkos. Only the latter satisfied the user's real-repository gate.

## Known gaps and evidence boundaries

- No editing, LSP, filesystem watcher, incremental parse cache, or language injection.
- Semantic completeness varies with project/indexer/toolchain. The recorded tkos run covered 338/340 Rust files, but that is one historical controlled run, not a universal guarantee.
- Engine Rust indexing was source-only/no-deps because `deno_core` vendor inputs were absent. `snapshot_profiles_test.rs` was an undeclared orphan. `tkreplica/test_support/fixture_paths.rs` was omitted through a path-module shape; its deeper cause remains uncertain.
- Python 3.10 was required while the development machine had 3.9; scip-clang still needed metadata and a manually installed binary.
- Go grouped declarations/interfaces and JSX elements are not foldable; expression-bodied functions naturally have no body to hide.
- Dark pin palette logic was not live visually verified in its implementation round.
- Native automation availability varied. Do not repeat stale claims that CUA always attaches; the final performance pass ended with `cgWindowNotFound`. The user's later acceptance is the strongest final interaction evidence.

## Evidence and sensible next work

- Exact chronology and acceptance: `plans/development-history.md` and `PROGRESS.md`.
- Syntax/query provenance: `plans/tree-sitter.md`, `Package.resolved`, `Sources/GrammarScanners/PROVENANCE.md`.
- Folding and benchmark: `plans/structural-navigation.md`, `SourceScrollViewTests.swift`.
- Indexing/support: `plans/scip-semantic-navigation.md`, `SemanticIndexService.swift`, `Indexers/`.
- Real tkos measurements: 2026-10-03 entries in `PROGRESS.md` and prior Paseo agent `fd0b558f-487f-4faa-8a95-c579f6a95eed`.

The latest live pass confirmed faint named-function shading in light mode, exact adjacent boundaries, outside-function clearing, folding, passive-scroll stability, and legibility under caret/highlights. The prior pass confirmed the visible caret, independent Context updates, word-selection/sidebar-focus hiding, visibility over pinned tint, Return/Back, and concise default rows. The earlier compact-only attempt stopped on native `noWindowsAvailable`; its full disclosure/narrow-width matrix was not repeated. Remaining manual checks cover expanded rows at normal and 220-point widths, independent expansion states, dark-mode caret/shading appearance, and the old README label (**File not indexed** with **Index Partial**). Exact steps and preserved evidence are in `plans/context-ui-review.md`. Respect the user's limited UI-access budget; stop if native inspection becomes complicated. Sensible future slices, only when requested, are filesystem-driven invalidation, deeper indexer coverage/robustness, multiple-definition chooser UX, and accessibility/dark-mode visual verification. Apply `swiftui-pro` before/after code decisions, `macos-design` for UI changes, and `typography-designer` for any new or changed type role.
