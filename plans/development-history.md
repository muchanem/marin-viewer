# Development history

This is a chronological record, not a claim that every historical validation remains current. Counts and timings below are what the responsible development round recorded. The documentation round did not rerun the app or tests.

## 1. Foundation: native read-only repository browser

The original product direction was a native macOS reader for unfamiliar codebases. The first implementation established repository/folder opening, recent folders, Finder drop and CLI launch; Git-aware file discovery with filesystem fallback; an expandable/filterable tree; and an immutable UTF-8 `SourceBuffer`. TextKit conversion was centralized at UTF-16 boundaries so line navigation, history and later parsers could retain byte-accurate positions.

The source view added original line numbers, native Find/copy, font zoom, exact browser-style Back/Forward positions, ripgrep repository search, manual reload and visible error states. SwiftPM is the source of truth; `make build/run/check/test` drive the app, `build/Radiology.app` is locally ad-hoc signed, and App Sandbox is disabled so child tools can run. Search is optional when `rg` is missing.

## 2. Swift Tree-sitter

The user next requested structural awareness without SCIP. Agent `d60a9896-8491-4d8c-b4da-979dcaa34b68` delivered asynchronous Swift parsing, query-driven syntax roles, declarations/scopes/outline/folds, cancellation and source-generation guards, malformed-source recovery, and tests protecting canonical byte ranges. Source remained immediately readable while parsing occurred. The round recorded 22 tests in seven suites, a signed build, and live UI checks.

## 3. Major-language Tree-sitter expansion

Agent `a3627f41-39ea-4082-bc06-fa1e365bc7e5` expanded structure to Rust, Go, Python, JavaScript/JSX, TypeScript/TSX, and Kotlin while retaining Swift. The result is eight grammar registrations and, currently, 31 Radiology query resources. JavaScript and Python scanner sources were vendored byte-identically because their upstream SwiftPM manifests did not compile those scanners; provenance is recorded beside them.

The round recorded 49 tests. It explicitly had no visual inspection because automation permissions were unavailable. Unsupported languages remained plain text. Old statements that syntax had no SCIP accurately describe this stage only; SCIP arrived later.

## 4. Structural navigation: viewer to code browser

The user prioritized hierarchical outline containment, click-to-declaration, source-scroll synchronization, Up/Down preview with Return commit, structural breadcrumbs, Fold to Definitions, and exact Back/Forward before SCIP. The user initially requested Fable for decisions/first code. Agent `267f6c85-7da4-41ac-80f4-d78239343721` oriented and planned, then was stopped when the user asked to switch to Sol before substantial code. Agent `fd0b558f-487f-4faa-8a95-c579f6a95eed` implemented and refined the UI. This established the continuing preference: Fable for large decisions/first cuts, Sol for UI testing/refinement.

The first structural pass recorded 52 tests. It used strict byte-range containment, passive synchronization that creates no history, committed structural anchors, focus-preserving jumps, fold reveal, and a 28-point disclosure target.

## 5. Folding and reveal correctness

User testing found hidden line numbers stacked on one another, the disclosure affordance too small, and outline jumps into collapsed symbols ineffective. The fixes moved the gutter into a dedicated `NSView` using clip-safe coordinates, enlarged targets to 28 points, unfolded hiding ancestors, forced layout before reveal, stabilized scroll anchors, and added a generation-guarded transient destination-line flash. This round recorded 54 tests.

The user then asked for every supported language's function bodies to start collapsed and for a re-collapse action. Default folds became one-time per loaded buffer; declaration containers remain open and signatures readable. **Collapse Functions** became ⇧⌘0 while **Fold to Definitions** remained ⌥⌘0. That round recorded 56 tests. This supersedes early descriptions of purely manual folding.

## 6. Native SCIP first cut

The user authorized app-owned semantic indexing rather than LSPs. Agent `5e1e19a7-8874-4cc9-b13e-04c96161f4b0` (Fable) made the architecture decisions and first implementation; Sol then took the UI/refinement pass.

Radiology detects projects, discovers installed/provisionable batch indexers, runs cancellable subprocesses without blocking browsing, stores caches outside repositories, and continues using stale data. A hand-written SCIP protobuf decoder normalizes documents, symbols, occurrences, definitions, references, and relationships; SCIP encodings convert to canonical bytes only at the semantic boundary.

The UI gained genuine Command-hover/Command-click, ⌃⌘J Go to Definition, exact Back, grouped Find References, ⌘T symbol search, Reindex/Cancel/Install, and diagnostics. There is no LSP or text-based semantic guessing. `rust-analyzer` supplies a batch `scip` command, not a live server. The first cut recorded 76 tests/14 suites. Swift, Kotlin, and Java semantic adapters were not implemented.

## 7. Real tkos Rust acceptance gate

The user made untouched `~/codebase/tkos` a hard gate: small named omissions were acceptable, but crashes, zero-document projects, or majority-missing directories were not. Fixture-only success did not qualify.

The controlled cold app run discovered 11 Cargo projects and indexed 338/340 Rust files: engine 28/29; phone-provisioner 1/1; agent/ffi 71/71; agent/harness 151/151; game 3/3; imap 3/3; mls 11/11; scene3d 3/3; spotify 5/5; storage 2/2; tkreplica 60/61. tkos stayed unchanged and Git-clean.

Engine used degraded `sourceOnlyNoDeps` indexing because Cargo could not resolve `deno_core`: required include-js vendor inputs were absent under `.scratch/js-runtime/vendor`. Vendoring and synthetic shadow manifests were rejected in favor of real manifest/features/cfg identity. `engine/rust/src/snapshot_profiles_test.rs` was an undeclared orphan. `modules/tkreplica/rust/test_support/fixture_paths.rs` was omitted through path modules; its deeper cause remains uncertain.

Real `app_image.rs` data contained 935 occurrences and 152 definitions; `PreparedApp` had 11 references. The mixed cache measured 389 documents, 63,224 symbols, and 16,615 searchable symbols. Discovery became shallow-first with a cap of 32 and explicit skipped-project reporting; independent failures preserve successes; diagnostics preserve head and tail; degraded cache remains Partial. Python 3.10 versus installed 3.9 and scip-clang prerequisites remained limitations. This round recorded 79 tests/14 suites.

## 8. Occurrence highlighting, quick files, and cfg-inactive code

Ordinary symbol click gained identity-accurate current-file occurrence drawing with a stronger active occurrence and subtler peers. Whitespace clears it; folds retain canonical ranges. That round recorded 83 tests/14 suites.

Cmd-K (Cmd-P alias) then gained case/diacritic-insensitive ordered-subsequence file matching, filename-aware ranking, cancellable off-main work, top-100 display with true total, keyboard/mouse activation, Escape and focus restoration. On real tkos, 6,721 files were discovered and `apimgrs` ranked `app_image.rs` first among 89 matches. Deferred row activation fixed AppKit table reentry.

A user screenshot exposed that `message` inside cfg-Android `android_log` did not highlight. Host SCIP legitimately omitted inactive code, and native double-click bypassed the old callback. After native selection, a drawing-only Tree-sitter fallback now finds exact identifiers inside the innermost function/closure, excludes strings/comments/other functions, and intentionally includes same-spelled shadowed locals. It never supplies definitions/references. Native evidence showed four highlights and whitespace clear. The combined picker/fallback round recorded 89 tests/15 suites.

## 9. Locked occurrence groups

Double-click now locks a group until any member is double-clicked again. Multiple stable teal, amber, violet and rose groups use translucent fill plus a 1.4-point stroke. Ordinary selection/whitespace leaves pins; Command-click does not toggle. Pins are session/document scoped by path, byte count/checksum and canonical ranges; changed content invalidates them and semantic arrival reconciles compatible fallback groups.

Native evidence showed four teal `message` and two amber `CString` occurrences; removing `message` left `CString`. This round recorded 93 tests/16 suites. Dark colors were deterministic in code but not live visually verified.

## 10. Fold-size cue and large-layout correction

The first subtle 2-point meter in a 68-point gutter failed the user's expectation and is historical only. A screenshot of `modules/agent/ffi/src/app.rs` also showed stacked numbers and blank space around the large function sequence near line 1453.

The final design is a 104-point gutter with separate 28-point disclosure, exact-count and line-number lanes. A 3-point neutral logarithmic meter ranges 6–22 points (capped at 256 hidden lines); a 9-point medium tabular capsule gives the exact count. Hidden newlines use null glyphs/zero advancement, effective folds are disjoint outer ranges, and the gutter uses each visible fragment's first real glyph. Inspection showed compact 1453 → 1734 → 1812 → 1829 → 1941 → 2062 → 2075 and counts 7/43/76/119/279 at normal/enlarged sizes. This round recorded 96 tests/16 suites.

## 11. Large-file folding performance

The user reported large `app.rs` functions taking upward of four seconds. Profiling found a per-character linear fold-range scan and whole-document glyph invalidation on every toggle, making tiny folds nearly as expensive as large ones.

The fix keeps sorted disjoint ranges with binary lookup, diffs effective unions, regenerates glyphs only for changed ranges, invalidates downstream layout as needed, and skips nested/no-op transitions hidden by a parent. Canonical bytes and compact layout did not change.

An opt-in AppKit benchmark on the real 4,880-line file forced `ensureLayout`/redraw. Three-pair median expand/collapse changed from .52/.33 to .062/.057 seconds for the large line-1453 fold, .34/.31 to .051/.050 for medium line 1734, and .30/.29 to .048/.047 for tiny line 1812. These isolated TextKit numbers are not a measurement of the user's four-second full-app interaction. Run with `RADIOLOGY_REAL_FOLD_BENCHMARK=1 swift test --filter realAppFoldPerformanceProbe`.

The round recorded `make check`, 97 tests/16 suites, signed build and packaged resources. Native automation could not attach (`cgWindowNotFound`), so it did not claim pointer-timed evidence.

## 12. User acceptance and documentation handoff

The user then said: “yeah you fixed it, you can settle at this point.” This is final acceptance of the folding issue, independent of the benchmark/automation limitation. The status heartbeat was deleted.

The documentation round rewrote the root README; added this history and `plans/agent-handoff.md`; refreshed PLAN.md; added acceptance and documentation status to PROGRESS.md; and reconciled materially stale statements. It changed no application code, tests, external tools, tkos content, or behavior and did not rerun builds/tests.

## 13. Pull request review

The user asked for the browser to track pull requests of the attached repository: a drop-down of the last N, a ⌘P number entry, highlighting of changed files, functions and added lines, and a per-file Before/After toggle, with the SCIP index "cloned and patched" for changed files. Fable 5.1 (Paseo agent) designed and implemented it in one round; GPT Sol tests the UI afterwards.

Measured first: tkos has 10,094 tracked files (168 MiB), 13 rust-analyzer strategies totalling about 220 s, and a format-2 index cache with no per-document byte provenance; fetching a PR head and merge base by SHA into an app-owned bare repository with alternates to the user's objects takes about a second; a worktree checkout 1.5 s. The clone-and-patch idea was kept at its honest granularity: a whole strategy (crate/module/project) is reused only when a recorded git-blob content digest proves identical bytes, otherwise regenerated whole; mixed runs are Partial. Before is syntax-only.

Delivered: `GitHubClient` (gh, timeouts), `ReviewRepository` (fetch by SHA, worktrees, Before blobs, eviction), `UnifiedDiff`/`FileChange`/`LineMap`, `PullRequestModel`, revision-aware `SourceLocation`/`SourceBuffer`/positions/history, metadata format 3 with digests and reuse, and the UI (toolbar menu, ⌘P sheet, Changes sidebar, Before/After control, gutter bars and washes, outline/tree dots, ⌥⌘B, ⌥⌘↓/↑, `--pull-request` launch argument). The round recorded 184 tests in 39 suites, including a real read-only tkos probe (#724 merged meanwhile with a new head, #723 merged, #725 at 744 files with renames). The first full-suite runs exposed main-actor starvation from synchronous git fixtures and a CRLF grapheme bug in the hunk parser; both were fixed.

## 14. Source filters (Hide Tests, Source Files Only)

The user asked to hide test code, including Rust test blocks in the middle of ordinary files, and to filter the Files sidebar down to source code. Opus 5.5 recorded the architecture in `plans/source-filters.md`, then implemented it:

- Two independent persisted toggles sit beside the Files filter field and in the View menu.
- Component-exact test-path and source-file classifiers drive a pruned Files tree with explicit, path-keyed expansion state.
- A Tree-sitter test-region detector covers Rust (three-valued `cfg` evaluation), Kotlin, TS/TSX/JS and best-effort Python.
- Hidden test regions join the existing fold union as a presentation projection, with a dimmed header, gutter capsule and clickable label.
- Navigation reveals its target's region, and Back stays exact.

Gates: 210 tests / 43 suites, signed 23:16:01 CDT. The real tkos probe matched GPT Sol's anchors (`app.rs` 803–833 with 834 production visible). Live UI acceptance belongs to GPT Sol (`plans/source-filters-ui-review.md`).
