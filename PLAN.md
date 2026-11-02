# Radiology documentation index and current state

Radiology is a native, read-only macOS repository browser. The active implementation is the root SwiftPM package, now tracked in Git on `main` for [tqbf/radiology](https://github.com/tqbf/radiology). A local nested `repo/` directory is an inherited, inactive starter copy, excluded from version control: do not edit it. The user explicitly authorized initializing Git and publishing the project after the documentation handoff. AGENTS.md normally prohibits agent merges; on 2026-10-11 the user explicitly authorized merging the accumulated reader-work publication to `main`.

## Current accepted state

**Marin viewer shell (2026-11-01, branch `mark/shell`):** opening a prepared wordbase PR
(⇧⌘O or `--viewer-pr N`) turns the reader window into the viewer: PR description, system map
and PR map above the split view, the step sidebar, the session panel in the inspector, review
notes and code windows. `ViewerStore` holds the PR and the state that the diff reader observes.
[Shell, seam API and merge mapping](plans/shell.md).

**Publication batch (2026-10-31):** the user requested bundling all local changes
and pushing directly to GitHub `main`. The starting local branch, local `main`
and fetched `origin/main` all pointed to `6d446b9`, allowing one new commit and a
normal fast-forward push without a PR merge. This batch includes all reader,
Code Paths, C/C++, seL4, indexing-personality, trait and inspector work described
below. [Publication scope and validation](plans/github-publication.md); newest
PROGRESS.md records this batch's checks. Earlier local/uncommitted descriptions
are historical.

**Code Paths in the left sidebar (2026-10-31):** Files / Code Paths / Search,
plus Changes during PR review. Import selects/reveals Code Paths; View > Show
Code Paths (⌃⌘P) restores a hidden navigation sidebar. Bookmarks retains its
independent right-pane visibility. Existing traces need no reimport; the earlier
inspector placement and competing-pane switch actions below are superseded.
[Current contract](plans/code-paths.md). **333 tests /77 suites**, signed build,
resource verification and live sidebar/import/navigation/recovery checks pass.
Relaunch the built app; newest PROGRESS.md records exact evidence and limits.

**Function visits expand bodies (2026-10-31):** committed reader jumps, including
Code Paths and Back, open the destination function and folded ancestors. Late
syntax and font updates preserve the caret; manual collapse survives ordinary
refreshes, and unrelated functions stay folded. [Behavior](plans/code-paths.md).
See newest PROGRESS.md for validation.

**seL4 Code Paths repair (2026-10-31):** exact supplied **91-step ARM trace**
resolves and navigates through the actual reader model on d419a119a. BEGIN_FUNC
assembly, preprocessor-damaged C body parsing and conditional source variants
are repaired. Imports hide Bookmarks; direct Show Bookmarks Instead / Show Code
Paths Instead and Hide actions persist pane choice. Native clicks, variant
selection, exact Back and pane switch/relaunch pass. **332 tests /76 suites**
pass excluding the known Files scroll assertion; signed build/resources and
light/dark renders pass. **Relaunch the built app; no trace reimport needed.**
[Updated contract](plans/code-paths.md); newest PROGRESS.md has exact evidence.

**Code Paths and keyboard help (2026-10-30):** persistent repository-associated
`file:function:description` traces with symbol-based navigation, paste/text-file
import and an optional right inspector pane. No line numbers are stored; native
acceptance followed the same function from line3 to line5 after source changes.
[Feature contract](plans/code-paths.md),
[generator skill prompt](plans/code-path-generator-prompt.md),
[complete keyboard reference](Sources/Radiology/Help/KeyboardShortcuts.md), also
in Help > Keyboard Shortcuts (⌘/). **16 focused tests /5 suites**, **326 tests /
75 suites excluding the known Files scroll assertion**, light/dark native
renders, live import/relaunch/navigation/Help, signed build and resources pass.
Relaunch the built app. See the newest PROGRESS.md entry for exact limits.

**Indexing personalities (2026-10-30):** Semantic Index now has native
**Default / seL4** selection and **Show Settings File**. Readable TOML drives
adapter limits/workers and the complete **67-configuration** seL4 recipe;
selection persists per attached checkout, including PRs. Reindex runs the
selected pipeline, with isolated inputs, exact settings provenance, separate
caches and configuration-aware reuse. Real generation, explicit Reindex and
warm reload preserve **598 documents /24,934 symbols /131,126 occurrences**.
seL4 is selected for the user's checkout; its new namespace is primed.
**313 tests /71 suites pass excluding one known Files scroll failure**;
final **9 targeted tests /3 suites**, light/dark native renders and signed
build/resource gates pass. Relaunch for the new picker.
[Current workflow and schema](plans/indexing-personalities.md).

**Original seL4 indexing job (2026-10-30, superseded above):** normal app cache primed with a compiler union
of **67 configurations /134 translation units**: **598 documents,24,934
symbols,131,126 occurrences**, all original-coordinate checks pass. All
**177 build-backed physical C files** are covered; 25 source/header paths
remain honestly Partial. Only upstream header generation requires preprocessing;
the index reads original sources through unity include wrappers. Separate
configuration runs retain conditional definitions lost by a combined run.
Reproduction/import recipe and Reindex limitation:
[seL4 indexing](plans/sel4-indexing.md). Five union tests and real cold/warm
acceptance pass; **306 app tests pass with one existing Files scroll test
excluded**. Compile/build/sign/resources pass; app session preserved.

**C/C++ best effort (2026-10-13):** no compilation database required.
Source-only GNU C11/C++20 defaults and inferred include paths produce actual
compiler identities, always marked Best effort/Partial including cache hits.
Real build databases retain priority; preparation is cancellable and memoized.
Actual tkfiasco: **15,669 indexed documents /523,683 symbols**, normal app
cache primed; cold 321.438 s/warm 18.144 s. **305 tests /67 suites** and
compile/build/strict signing/resources pass, signed 17:56:17 CDT. Relaunch the
upgraded app. [Contract and current evidence](plans/clang-best-effort.md);
newest PROGRESS.md records full validation and limits.

**C/C++ support (2026-10-13):** official C 0.24.2/C++ 0.23.4 grammars and
five query roles, recursive declaration names and mixed headers. scip-clang
0.4.0 gains checksum-verified managed Apple Silicon installation, build
database discovery, temporary logs and persisted Partial compiler coverage.
tkfiasco can use best-effort defaults; real build inputs improve coverage;
Fiasco source directives and upstream extern-C gaps remain explicit.
**301 tests /66 suites**, check/build/strict signing and all ten packaged
grammars pass. [Contract and validation](plans/c-cpp-support.md); newest
PROGRESS.md has gates. Relaunch the built app for the registry.

**Dense Trait Implementations (2026-10-11):** one caption/count and a flat
22-point list of type/file:line Buttons. Single click opens an impl with exact
Back; separate trait/file headings, disclosures, preview views/state/tasks and
routine footer removed. Full source context/coverage remains in help with a
gap indicator. **291 tests /63 suites pass sequentially**; native row-count/
height, primary action/Back and six width/appearance renders verified;
check/build/sign/resources pass, signed **17:14:26 CDT**.
[Current contract](plans/rust-trait-implementations.md).

**Inspector pane controls (2026-10-11):** persistent Panes menu and View >
Context Panes checked choices for References, Definition/Outline,
Implementations and Bookmarks. Active regions reclaim height; all-off recovery,
contextual detail fallback and enabling-from-View inspector recovery retain
reader and model state. All 16 combinations/native dividers and light/dark
renders verified. **291 tests /63 suites pass with --no-parallel**; parallel
runs hit the Files manual-scroll timing assertion, which passes alone and with
the pane suite. Check/build/sign/resources pass; signed **16:39:26 CDT**.
[Contract and evidence](plans/inspector-pane-controls.md).

**Rust trait implementations (2026-10-11):** contextual middle inspector pane,
precomputed during semantic publication and persisted by exact source/semantic
digests. Exact identities cover aliases, qualified paths, blanket and negative
impls; changed destinations are rejected and exact Back is preserved. Native
dividers and light/dark rows verified; **288 tests /62 suites** pass. Read-only
348-file probe: 585 blocks/78 traits, cold 2.639 s, warm 0.413 s with no reparsing.
Macros/configuration gaps remain explicit. [Contract and evidence](plans/rust-trait-implementations.md).

**Files follows navigation (2026-10-11):** Files expands parents, highlights and
centers the current document after bookmarks/search/other jumps and returning
to Files. Exact caret/history/revision survive; passive caret movement preserves
manual list browsing. Current-file filter exceptions and Before-only paths keep
settings unchanged. Actual native List selection/scroll tests pass. **277 tests /
59 suites**, check/build/strict signing/resources; signed **15:37:26 CDT**. Local
with x-key work on codex/toggle-current-function.
[Contract and evidence](plans/files-sidebar-navigation.md).

**Current-function fold key (2026-10-11):** plain x in the source reader toggles
the innermost named function's own body fold, using existing state. Expanding a
hidden function also opens folded ancestors; siblings, source bytes, selection
and navigation remain unchanged. Outside/unfoldable functions are unchanged;
modified keys and other input fields retain native handling, hold-repeat is
suppressed. **273 tests /58 suites**, check/build/strict signing/resources pass;
signed **15:08:18 CDT**. Local branch
`codex/toggle-current-function`; [contract and evidence](plans/function-fold-key.md).

**Published to GitHub main (2026-10-11):** all accumulated work merged through
[PR #1](https://github.com/tqbf/radiology/pull/1), explicitly authorized by the
user after initially requesting a push. Feature commit `3b8f7f5`, merge `dfc877a`
at **14:53:25 CDT**; local main fast-forwarded to the confirmed GitHub merge.
The preceding 269-test/signed-build gates cover this snapshot. Publication docs
supersede earlier rounds' local/uncommitted statements.
[Scope, commits and validation](plans/github-publication.md).

**Repository/PR bookmarks (2026-10-11):** third independently scrolling,
resizable Context pane; ⌘D toggles the exact caret, ⌘0–⌘9 use the first ten
ordered bookmarks. Native drag and context-menu reordering persist per canonical
attached checkout/PR number, with checkout separate. Before/After and exact Back
are preserved; changed source uses bounded anchors or an explicit error.
Normal/Critical now use ⌥⌘1/⌥⌘2. Nested native splits pass both divider checks.
**269 tests /57 suites**, light/dark renders, check/build/strict signing/resources
pass; built **14:41:15 CDT**. Physical drag/menu/shortcut checks remain unverified;
desktop automation is unavailable. [Contract and acceptance](plans/bookmarks.md).

**Caller identity pills and cycle repair (2026-10-11):** each caller is a
clickable capsule colored from a fixed 12-color palette by a deterministic
method-name/full-file-path hash. Colors persist across branches/relaunches;
light/dark text hierarchy and native navigation remain. Recursive branches now
stop before rendering a repeated callable, checked by semantic identity and
canonical declaration location; distinct same-named functions remain separate.
**263 tests / 55 suites**, three-width light/dark renders, check/build/strict
signing/packaged resources pass; built **13:47:46 CDT**. Retried live automation
still reports missing `@oai/sky`; mouse checks remain unverified.
[Palette and cycle evidence](plans/caller-pills.md).

**Reference caller trees and resizable inspector (2026-10-11):** reference
disclosure traces the containing callable backward through exact SCIP identities
and parsed calls, preserving branches and marking recursion/unknown boundaries.
No depth cutoff; larger trees continue with Trace more callers. Native VSplitView
resizes independently scrolling References and Definition/Outline panes.
**260 tests / 54 suites** pass, including 270-level continuation, caller/Back
navigation and native divider resizing. Three-width light/dark component renders
pass; check/build/strict signing/packaged resources pass, built **13:31:01 CDT**.
Physical UI remains unverified because desktop automation failed to start.
[Contract and evidence](plans/reference-call-trees.md). This supersedes the
2026-10-08 outer scrolling layout below.

**Inspector refinement (2026-10-08):** stronger symbol title and
small section headings, compact top-stacked layout, exact-identity definition
deduplication, stronger snippet contrast and faint appearance-aware section
tints. Native PR758 verifies stacked layout, matching-name deduplication,
reference disclosure/Return/Back; three-width light/dark renders pass.
**253 tests / 52 suites**, check/build/sign/resources pass; built **22:59:05 CDT**.
One preexisting highlight timer test failed initially, then passed alone and in
the unchanged full rerun. Different-target native check remains unverified.
[Inspector contract and evidence](plans/inspector-refinement.md).

**Toolbar and Changes sidebar refinement (2026-10-08):** selected-
value Normal/Critical dropdown, Before/After beside it, menu-only source filters;
tab-like Changes/Files/Search without Browse; clearer filenames/status/counts,
selection, summary spacing and filter-aware footer. Native PR758 verifies layout,
mode/revision/filter controls, tab clicks and keyboard Files→Search. Three-width
light/dark row renders pass. **253 tests / 52 suites**, compile/build/sign/resources
pass; built **17:35:01 CDT**. Separate review app closed; user reader preserved.
[Current task and evidence](plans/sidebar-refinement.md).

**Source breadcrumbs (2026-10-08):** source header
reserves a fixed trailing area for change/collapse controls and compacts paths
from the beginning, retaining nearby directories and enclosing declarations
one at a time as space allows. File/final symbol get priority at tight widths;
full location/declaration jumps remain in the ellipsis menu. Live PR758 now shows
crates/harness-core/src/file/Nomex/admit_call; Before/After/menu and five-width
light/dark renders pass. **253 tests / 52 suites**, compile/build/sign/resources
pass; built **17:02:10 CDT**. User reader preserved; review app closed.
[Layout and validation](plans/source-breadcrumbs.md).

**Reader session restoration (2026-10-08):** normal relaunch reopens the attached
repository and last confirmed PR, resolving fresh metadata. Exit PR remembers
local checkout; CLI/manual choices win, and failed restores retain their saved
PR for retry. Real separate-instance quit/relaunch restored tkos #758 without
arguments; the current user's #758 record is saved for the first upgraded launch.
**253 tests / 52 suites**, check/build/sign/resources pass; built **16:36:48 CDT**.
[Lifecycle and acceptance](plans/session-restoration.md).

**Compact source gutter (2026-10-08):** user steered toolbar work
to narrow the existing 104-point gutter to **72 points** and print only every
fifth canonical line plus the actual caret line. Native draw/fold/scroll tests
pass; live PR758 Go to Line7 / Down to8 confirms sole non-fifth label updates.
Combined gates **246 tests / 51 suites**, build/sign/resources; signed
**16:10:23 CDT**. Source font unchanged; counts defer to tooltips when cramped.
[Rendering contract](plans/source-gutter.md).

**Toolbar grouping (2026-10-08):** native navigation/repository,
labeled PR context with compact refresh and Exit PR inside its menu, and viewing
tools with grouped filter/search actions. Duplicate PR subtitle removed; source
Before/After remains in the breadcrumb row. Native review verified grouping,
menus, filter binding, left-sidebar button/Ctrl-Cmd-S and Exit PR. Detail-scoped
toolbar avoids misplaced sidebar tools/duplicate toggle. Narrow resizing remains
unverified after two native drag errors. Same 246-test/signed gates above.
[Contract and review](plans/toolbar-layout.md).

**Kotlin workspace repair (2026-10-08):** user's real app exposed
a directory-symlink copy/hash failure missed by earlier manual compiler probes.
Directory/internal-file links, dangling external Markdown links and complete
tracked build inputs are repaired. The actual PR758 SemanticIndexService path
passes: **2,088 source documents, 18 references / 4 files**, generated with honest
Partial coverage, cache and cleanup verified. Gates **244 tests / 50 suites**,
compile/build/strict signing/resources; signed **01:10:35 CDT**. No physical UI
check/restart; relaunch and reopen PR758. See PROGRESS.md and
[the Kotlin contract](plans/kotlin-semantic-indexing.md).

**Kotlin semantic support (2026-10-07):** compiler-backed Gradle indexing now
supports AGP9 built-in Kotlin; the managed Kotlin2.4.20-compatible tool is
installed here. Disposable real-input builds, pre/post byte verification,
snapshot-only document publication, UTF-16 adapter defaults on generation/cache/
reuse, and persisted Partial build coverage preserve PR identity. Real PR758
After `addSecrecyTag` resolves to SecrecyCtx.kt:18 with 18 references in 4 files;
broader build emits 2,379 compiler documents with two native setup failures,
honestly Partial. Native-component PR caret/reference/definition/Back tests pass.
Gates **241 tests / 50 suites**, compile/build/strict signing/resources; signed
**18:36:00 PDT**. Physical UI remains unverified; relaunch is required to use
the new registry. [Current contract and exact evidence](plans/kotlin-semantic-indexing.md).

**Context inspector recovery (2026-10-07):** native drag-to-collapse now has a
scene-bound **View > Show Context Inspector / Hide Context Inspector** command
and **⌥⌘I** shortcut. Toolbar labels match the current presentation state;
recovery stays available without a source file. ⌃⌘I remains Reindex. Gates:
**234 tests / 47 suites**, compile/build, strict signing and packaged resources;
signed **17:47:35 PDT**. Physical drag/reopen remains unverified. See
[the current sidebar contract](plans/context-sidebar.md) and the newest
PROGRESS.md entry for validation and the manual drag/reopen checks.

The user confirmed on 2026-10-04 that the latest large-function folding fix works: “yeah you fixed it, you can settle at this point.” The recurring status heartbeat was deleted and must not be recreated unless the user asks. A subsequent request now authorizes the caret-driven Context sidebar described below.

The caret-driven **Context inspector** is implemented by Opus 5.5 and replaces the Outline/Symbol toggle. Its upper region tracks the enclosing declaration and references; its lower region shows the selected semantic definition or the outline. Entries are **one line by default**, with disclosure for signatures, documentation, and source context. The lower heading is **Definition**; “Under Caret” was removed. Selecting references stays compact; Return commits navigation. Source Return/Enter goes to definition, and Cmd-[ restores the exact departure caret even after scrolling. A subtle, steady source caret makes character-level keyboard movement visible. Gates after the caret round passed with **129 tests in 21 suites**. A faint shade under the caret's innermost function or method followed. Its gates pass: **132 tests in 22 suites**, `make check`, signed build, strict codesign, and packaged resource verification. GPT Sol verified the faint shade live in light mode on untouched tkos: correct function boundaries, outside-function clearing, fold collapse/expansion, passive-scroll stability, and readable caret/highlight layering. Dark-mode shading remains unverified; see the newest PROGRESS.md entry. GPT Sol verified the caret live on untouched tkos: arrows update Context without navigation, word selection and sidebar focus hide the caret, pinned tint does not obscure it, and Return/Back still works. The same pass confirmed concise default rows and the Definition heading. Full disclosure and narrow-width acceptance, the README availability-label check, and dark-mode caret appearance remain manual; see [the UI review](plans/context-ui-review.md) for evidence and exact checks. See [the implementation plan](plans/context-sidebar.md) and the newest PROGRESS.md entry. `/Users/tqbf/codebase/tk/tkos` remains read-only. Changes are local and uncommitted.

**Critical Lens (2026-10-04, Fable 5.1):** a `Normal | Critical` source-mode control (toolbar segmented control, View menu ⌘1/⌘2), a draw-time projection that recedes known runtime plumbing (stage one, verified live by GPT Sol; see [Sol's review](plans/critical-lens-ui-review.md)), and now function summaries, a bounded critical frontier with via paths and honest coverage, an automatic Critical section in the Context inspector, an automatic hover popover on callables, and reachable-critical counts in the fold gutter and outline (stages two and three). Call edges come only from parsed call sites resolved to SCIP identities; closures and nested functions own their own sites; unknown callees and closure-owned calls make counts partial, never a proven zero. Gates: `make check`, **161 tests in 32 suites**, signed build (2026-10-04 16:19:59), strict codesign, and packaged resource verification. Sol attempted the final native review, but attachment failed with `-10005: cgWindowNotFound` on both the initial attempt and the single permitted recovery. UI work stopped within the user's tooling limit. Implementation and model/build gates are complete; summaries, hover, and counts remain visually unverified. [Sol's review](plans/critical-lens-ui-review.md) contains the exact manual checks and screenshot requests; the final build is left available. See [the Critical Lens design](plans/critical-lens.md) and the newest PROGRESS.md entry.

**Critical rendering refinement (GPT Sol):** the user superseded the earlier protect-all-syntax behavior. Critical now aggressively dims non-call source and ordinary runtime calls; only actual parsed critical/unknown call-name tokens remain prominent. Unresolved syntactic call names stay visible without invented identities/edges. Alpha is 30% light / 38% dark; no layout/storage/navigation changes. Native same-viewport `app.rs:115–139 execute_future` comparison succeeded; the user independently accepted it (“this is much better”). Existing pins/line tint and concise upper call names/independent lower Definition were observed. Dark mode, new mark toggles, hover navigation and folded-count semantics remain unverified; shared-reader activity ended live work. Gates pass: **163 tests / 32 suites**, check/build/strict codesign/empty-env 8-grammar resources; signed binary **16:53:36**. See [the review](plans/critical-lens-ui-review.md) and [current rendering contract](plans/critical-lens.md). Earlier projection/contrast descriptions are historical and superseded.

**Latest Critical Lens change:** the user removed its sidebar depiction. The sidebar now behaves identically across Normal/Critical: concise declaration/references and Definition/outline, with existing disclosures/navigation. No Critical call/frontier/status section, lower summary or outline density counts remain. Sidebar-only work/state/components are removed; source hover and fold-gutter computation remain. Call-focused rendering, toolbar and marks are preserved. Actual gates: **164 tests / 32 suites**, check/build/strict codesign/empty-env resources (8 grammars), signed **17:05:05**. Live check not attempted to avoid disrupting the user's shared reader. Earlier sidebar feature descriptions above are historical and superseded; see [current contract](plans/critical-lens.md) and [evidence](plans/critical-lens-ui-review.md).

**Hover interaction repair:** navigable popup titles and whole rows are now Buttons instead of passive names with small trailing links. Stable content hosting, native full-popover tracking and a source-to-popup transit region preserve entry/loading. External targets stay unavailable; existing exact-caret navigation/Back is retained. Gated **166 tests / 33 suites**, check/build/strict codesign/resources (8 grammars), signed **17:21:39**. Physical click verification remains unverified: native tooling attached to the old shared reader even after one full-path recovery, so live work stopped. No sidebar lens content restored. See [native review and manual steps](plans/critical-lens-ui-review.md).

**Latest ordinary outline change:** all file callables, including nested functions/methods, appear first sorted largest-to-smallest by signature-to-end line span (source-order ties), with quiet one-line `n L` counts. Non-callables remain in a native hierarchy without duplicate functions. Cache keys include both paths as well as bytes/symbols. Original declaration navigation and Normal/Critical parity remain. Gates **169 tests / 34 suites**, check/build/strict signing/empty-env resources; signed **17:35:04**. Live outline verification remains manual because native attachment selected the user's older reader; no interaction was attempted. The previous hover physical-click limitation remains explicit. See [outline architecture](plans/structural-navigation.md), [handoff](plans/agent-handoff.md) and [review](plans/critical-lens-ui-review.md).

**Pull request review (2026-10-04, Fable 5.1; gated at 184 tests / 39 suites, signed 19:56:31 CDT; UI unverified, Sol acceptance pending):** the toolbar **Pull Request** menu lists the last 25 PRs (open/merged/closed) of the attached repository through read-only `gh`; ⌘P opens one by number (the old ⌘P file-picker alias is gone; ⌘K remains). After is the pinned head SHA checked out into an app-owned worktree; Before is GitHub's merge base, materialized per changed file. A **Changes** sidebar segment, file-tree and outline dots, green/red gutter bars and line washes, a per-file **Before | After** control (⌥⌘B), and ⌥⌘↓/↑ change navigation make up the UI. The After snapshot is indexed with per-strategy exact-bytes reuse (git blob digests, metadata format 3); mixed reused/regenerated runs are Partial; Before is syntax-only and never receives mapped semantics. Design, measured facts, identities, and acceptance cases: [plans/pull-request-review.md](plans/pull-request-review.md).

**PR acceptance repairs (GPT Sol, latest):** full pinned blob hunks prevent rename-path contamination; whole-repository dependency-context digests reject unproven sibling reuse; mixed reuse Partial survives cache reload/refresh; refresh preserves revision options; PR failures have native recovery alerts and file guidance uses Cmd-K. Gates **186 tests / 39 suites**, check/build/strict signing/empty-env resources; signed **20:07:43 CDT**. Real #724/#723/#725 backend probes and actual phone-provisioner After Rust generation (one document, 3,711 valid occurrences), matching reuse and context-change regeneration passed. Native attachment selected the user's older pinned reader; no UI actions/screenshots. Full PR UI/GUI cancellation and previous hover/outline limits remain open. [Acceptance evidence/manual checklist](plans/pull-request-ui-review.md); [current contract](plans/pull-request-review.md). Earlier project-local 15/16 reuse estimate is superseded by conservative repository-context policy.

**Latest PR affordance:** visible **Exit PR** (title and return icon) beside the selector while active/loading, using existing exit/cancel to local checkout, with pending error cleanup. No Git branch switch or misleading main label. Gates **186/39**, check/build/strict signing/env-i resources; signed **20:18:12 CDT**. No native attempt; manual check recorded in [PR UI review](plans/pull-request-ui-review.md).

**Source filters (2026-10-04, Opus 5.5; model/build gates passed; UI unverified, GPT Sol acceptance pending):** two independent, persisted toggles beside the Files filter field and in the View menu. **Hide Tests** (⌃⌘T) hides recognized test files/directories from the Files tree. It also hides syntax-detected test regions inside ordinary source as a fold-union projection: a dimmed header line, a gutter disclosure with a hidden-line count, and a quiet clickable label. Detection covers Rust `cfg(test)`/test attributes (three-valued cfg logic, mid-`impl` helpers), Kotlin annotations/test classes/Kotest, TS/TSX/JS framework calls with binding checks and Vitest in-source blocks, and best-effort Python `TestCase`/pytest. Explicit navigation reveals the region; Back stays exact; hidden declarations leave the outline. **Source Files Only** (⌃⌘O) prunes the tree to code/headers outside artifacts, dependencies and generated output. ⌘K, Search, Changes, Go to Symbol and indexing still cover every file. Gates: **210 tests / 43 suites** (including 3 opt-in tkos probes that skip by default; run separately and passing), check/build/strict codesign/empty-env resources; signed **23:16:01 CDT**. Real tkos probe: app.rs 35–43, 803–833 (834 production visible), 3424–EOF; the whole-repository sweep found no false positives among the non-Rust hits. Design and limits: [plans/source-filters.md](plans/source-filters.md); Sol's acceptance: [plans/source-filters-ui-review.md](plans/source-filters-ui-review.md).

**Source-filter acceptance repairs (latest, GPT Sol):** narrow pytest test_ detection, preserve Vitest production else, refresh label hit identities at unchanged geometry, reject hidden headers inside outer folds. Actual AppKit/detector regressions pass; **213 tests / 43 suites**, check/build/strict signing/env-i resources, signed **23:23:22 CDT**. Two targeted real-tkos probes rerun successfully. Native attachment/recovery selected older #691 reader; no interaction/screenshots, visual acceptance still open. [Review/manual checks](plans/source-filters-ui-review.md), [current contract](plans/source-filters.md).

**Latest source-filter scope fix (2026-10-05, GPT Sol):** PR Changes now shares both SourceFilters options with Files; canonical diffs remain full. Rename/copy retained if either available path passes; deleted uses Before. Compact controls, visible counts/totals and filtered-empty reset; selection/filter changes preserve current reader/revision/history. Gates **216/44**, check/build/strict signing/resources/diff check; signed **2026-10-05 19:00:13 PDT**. No native retry; [scope/review](plans/source-filters-ui-review.md) and [PR contract](plans/pull-request-review.md). Earlier Changes-unfiltered descriptions are superseded.

**Latest PR source affordance (2026-10-06, GPT Sol):** previous/next changed-block icon buttons beside Before/After, shared directional availability with ⌥⌘↑/↓. Skip current hunk, nearest from gaps, no wrap; exact revision/content guards, reachable empty-side EOF anchors, observable genuine-caret updates and exact Back departure. Breadcrumbs scroll without consuming reader height. Gates **220/45**, check/build/sign/resources/diff; signed **14:22:51 PDT**. Native attachment/recovery selected older #753 reader; no interaction/screenshots. [PR contract](plans/pull-request-review.md), [UI/manual evidence](plans/pull-request-ui-review.md).

**Latest PR default visibility (2026-10-06, GPT Sol):** changed function/block folds and ancestors initially open once matching exact-document syntax/hunks are available. Header/attribute/decorator ownership is parsed; sibling closures stay folded. Manual choices (including pending diff and new bulk commands) win; fresh coordinators don't replay old commands. Hide Tests stays hidden; late layout preserves viewport/selection, discards obsolete navigation markers and yields to newer jumps. Gates **227/46**, check/build/strict signing/resources/diff; signed **14:47:45 PDT**. No native launch/attempt; component proof and exact manual PR anchors in [review](plans/pull-request-ui-review.md), [fold contract](plans/structural-navigation.md), [PR contract](plans/pull-request-review.md).

**Latest PR refresh (2026-10-06, GPT Sol):** visible Refresh PR / ⌘R fetches current metadata/head/merge-base while old reader stays usable; Refresh List separate, repository reload outside PR. Same head+base is metadata-only. Changed snapshot prepared atomically with protected worktrees, latest reader (including pending source load), exact-byte/Git-line restoration, proven renames and honest revision/missing fallback. SHA-old trails/data cleared, byte-proven current pins/options retained; failures retry refresh intent, cancellation/stale requests drop. Gates **234/47**, check/build/strict signing/resources/diff; signed **20:52:31 PDT**. No live attempt/remote refresh; [PR contract](plans/pull-request-review.md), [UI/manual evidence](plans/pull-request-ui-review.md).

The app icon now uses the supplied root `RADIO.png`; Make regenerates all macOS sizes when that image or the icon script changes. The icon-stage signed bundle was rebuilt at **16:42:51** (preserved in the subsequent call-focused build) and registered with LaunchServices. Compile, 161 tests/32 suites, signing, packaged resources, and decoded icon variants pass; application source and the final Critical Lens UI acceptance status are unchanged. See [the build guide](plans/build-system.md) and the newest PROGRESS.md entry.

Delivered behavior includes repository opening/recent/drop/CLI launch, Git-aware discovery, read-only TextKit source, ripgrep search, exact history, Tree-sitter structure for ten grammars, structural navigation and folding, fuzzy file lookup, and app-owned SCIP generation/navigation. The current fold gutter is 104 points wide with separate 28-point disclosure, exact hidden-line count, and canonical line-number lanes; the earlier 68-point/faint 2-point meter was superseded. Large-fold membership is binary-searched and glyph/layout invalidation is limited to changed ranges. Ordinary and locked occurrence highlighting coexist with native selection; a function-local Tree-sitter fallback covers parsed occurrences absent from SCIP without becoming a semantic guess.

The fresh checkout/build gate on SHEFFIELD (2026-10-04, macOS 26.5 / Swift 6.3.3) passed `make check`, 97 tests in 16 suites, a signed build, strict code-sign verification, and packaged verification of eight grammars/31 query files. Bundled builds now explicitly select SwiftPM's `swiftbuild` backend, matching the successful Swift 6.4 build on ELSTON; see [the build guide](plans/build-system.md). The user’s earlier acceptance is separate evidence that the reported fold interaction is fixed. See PROGRESS.md and the development history for the exact boundary.

## Required reading order

1. [README.md](README.md) — product usage, requirements, commands, shortcuts, supported languages/indexers, caches, and troubleshooting.
2. [PROGRESS.md](PROGRESS.md) — newest-first evidence log, including user acceptance and historical validation counts.
3. [plans/agent-handoff.md](plans/agent-handoff.md) — architecture map, invariants, key files, validation, gaps, and working constraints.
4. [plans/development-history.md](plans/development-history.md) — chronological development rounds and superseded behavior.
5. The subsystem document relevant to the next task.

## Subsystem documentation

- [plans/indexing-personalities.md](plans/indexing-personalities.md) — Default/seL4 UI, persistent repository choice, editable TOML, packaged pipeline, isolated execution, cache/reuse identity and validation.
- [plans/sel4-indexing.md](plans/sel4-indexing.md) — prepared seL4 configuration matrix, original-source unity wrappers, compiler union/local identities, verified app cache, reproduction and refresh limitations.
- [plans/clang-best-effort.md](plans/clang-best-effort.md) — automatic C/C++ semantic indexing without build information, inferred input policy, persistent coverage labels, cancellation, cache transitions and real validation.
- [plans/c-cpp-support.md](plans/c-cpp-support.md) — C/C++ grammars and query roles, recursive declarators, header routing, managed scip-clang installation, compilation database discovery, coverage, tkfiasco limits and validation.
- [plans/inspector-pane-controls.md](plans/inspector-pane-controls.md) — persistent checked pane menus, contextual detail fallback, all-off recovery, dynamic native splits and retained reader/pane state.
- [plans/rust-trait-implementations.md](plans/rust-trait-implementations.md) — contextual pane, advance indexing and persistent cache, identity/freshness/navigation contracts, coverage, measured performance and validation.
- [plans/source-breadcrumbs.md](plans/source-breadcrumbs.md) — adaptive path/declaration retention, fixed revision area, type hierarchy, and visual acceptance.
- [plans/session-restoration.md](plans/session-restoration.md) — last repository/PR persistence, startup precedence, failure recovery, and real relaunch acceptance.
- [plans/source-gutter.md](plans/source-gutter.md) — compact gutter, fifth-line/caret numbering, count fitting, typography and native draw verification.
- [plans/toolbar-layout.md](plans/toolbar-layout.md) — native toolbar groups, repository/PR/search menus, type hierarchy and visual acceptance.
- [plans/kotlin-semantic-indexing.md](plans/kotlin-semantic-indexing.md) — requested Kotlin compiler-backed indexing, Android Gradle compatibility, read-only isolation, and validation.
- [plans/architecture.md](plans/architecture.md) — layers, actors, canonical coordinates, and lifecycle.
- [plans/design-system.md](plans/design-system.md) — native macOS layout, type roles, color, source and gutter presentation.
- [plans/build-system.md](plans/build-system.md) — SwiftPM, bundle assembly, signing, optional release pipeline, and external tools.
- [plans/tree-sitter.md](plans/tree-sitter.md) — grammar versions, query resources, parsing contract, fallbacks, and syntax limits.
- [plans/structural-navigation.md](plans/structural-navigation.md) — outline synchronization, breadcrumbs, folding, reveal behavior, gutter geometry, and performance.
- [plans/context-sidebar.md](plans/context-sidebar.md) — caret-driven Context inspector: identities, reference preview/commit, caret-vs-viewport contract, caches, validation, real tkos results, and limits.
- [plans/context-ui-review.md](plans/context-ui-review.md) — GPT Sol's native UI/design evidence, initial defects, final repaired-build recheck, screenshots, and remaining manual checks.
- [plans/critical-lens.md](plans/critical-lens.md) — Critical Lens: measured SCIP/Tree-sitter facts, architecture and API boundaries, classification precedence and profiles, override persistence, draw-time projection, implemented summaries/call graph/frontier/hover/gutter contracts, validation, and limits. See [plans/critical-lens-ui-review.md](plans/critical-lens-ui-review.md) for native stage-one evidence, screenshots, contrast judgment and coverage limits.
- [plans/scip-semantic-navigation.md](plans/scip-semantic-navigation.md) — SCIP decoder/model, strategy discovery, adapters, provisioning, cache/freshness, revision indexes and exact-bytes reuse, navigation, occurrence highlighting, and limits.
- [plans/pull-request-review.md](plans/pull-request-review.md) — pull request review: measured tkos/gh/git facts, the strategy-level index reuse assessment, identities (attached root vs. snapshot roots, revisions on locations), components, minimal UI, behavior contract, sequence, and acceptance cases.
- [plans/scip-ui-handoff.md](plans/scip-ui-handoff.md) — historical first-cut UI test handoff; consult current PROGRESS/handoff before treating its open items as current.
- [plans/source-filters.md](plans/source-filters.md) — Hide Tests and Source Files Only: options/persistence/scope, path classifiers, per-language Tree-sitter test detection, fold-union presentation, reveal/navigation/identity contract, tests and limits. Sol's live acceptance: [plans/source-filters-ui-review.md](plans/source-filters-ui-review.md).
- [plans/quick-file-picker.md](plans/quick-file-picker.md) — Cmd-K/Cmd-P search/ranking/lifecycle.
- [Sources/GrammarScanners/PROVENANCE.md](Sources/GrammarScanners/PROVENANCE.md) — vendored JavaScript/Python scanner sources.
- [radiology.plan.md](radiology.plan.md) — original long-form product specification; useful direction, not current completion status.
- [treesitter.plan.md](treesitter.plan.md) — original Swift-first Tree-sitter request, preserved as history.
- [plans/roadmap.md](plans/roadmap.md) — delivered scope and possible future slices.
- [SWIFTUI-RULES.md](SWIFTUI-RULES.md), [PROBLEMS.md](PROBLEMS.md) — inherited implementation lessons and pitfalls.
- [plans/renaming.md](plans/renaming.md) — historical template rename notes; not an onboarding step.

## Maintenance rules

- Keep this file the master index; put deep documentation under `plans/` and update PROGRESS.md after work.
- Read and follow AGENTS.md. Use `swiftui-pro` before and after code decisions, `macos-design` for UI decisions, and `typography-designer` whenever setting type. A documentation-only description of existing behavior does not authorize redesign.
- Preserve canonical UTF-8 byte locations and convert only at boundaries. Do not make semantic navigation guess from spelling.
- Never edit the viewed repository during indexing tests. In particular, do not vendor dependencies into tkos or synthesize shadow manifests to conceal real project failures.
- Do not present old test totals as current. Label every recorded count/timing by its development round and say when no fresh test run was performed.
