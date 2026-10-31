# Caret-driven Context inspector

**Pane visibility, 2026-10-11:** the inspector's persistent Panes menu and
View > Context Panes enable/disable References, Definition/Outline,
Implementations and Bookmarks. Preferences persist app-wide; remaining panes
reflow without blank splits. All-off recovery and contextual detail fallback
preserve source/history and row/disclosure/bookmark state. See
[inspector-pane-controls.md](inspector-pane-controls.md).

**Current layout, 2026-10-11:** the inspector now has References,
Definition/Outline/Implementations and repository/PR Bookmarks in two nested native VSplitViews.
Both horizontal dividers resize the independently scrolling panes. ⌘D adds a
bookmark; reordered first-ten entries use ⌘0…⌘9. Source modes use ⌥⌘1/⌥⌘2.
See [bookmarks.md](bookmarks.md) for scope, persistence, native split tests and
current acceptance limits. Rust trait contexts show precomputed Implementations
in the middle pane; References and Bookmarks remain available. The caption is
Trait Implementations; dense flat type/file:line rows navigate with one click
or Return, without a trait subheading or disclosure. Coverage stays in help
and a gap indicator, and exact Back remains; see
[rust-trait-implementations.md](rust-trait-implementations.md). Other contexts
retain Definition/Outline behavior;
reference disclosure now includes the containing callable's incoming caller
tree. Existing symbol/section type hierarchy, exact-identity deduplication and
faint backgrounds remain. See [reference-call-trees.md](reference-call-trees.md)
for the current contract and tests; [inspector-refinement.md](inspector-refinement.md)
records the preceding hierarchy/contrast work.

Implemented 2026-10-04 by Opus 5.5. It replaces the inspector's Outline/Symbol
segmented toggle with one **Context** inspector made of two regions in a native
`VSplitView`. Each region updates independently. The implementation agent did
not launch or inspect the app; GPT Sol performed the live UI and visual review.
See [the UI review](context-ui-review.md) for observed behavior, final-build
repair confirmation, screenshots, and remaining manual checks.

## Collapsing and restoring the inspector (2026-10-07)

The outer inspector uses SwiftUI's native collapsible trailing column. Its
220/280/420-point minimum/ideal/maximum widths apply while expanded; dragging
past the collapse threshold can hide the entire column. A minimum width does
not prevent native collapse. See Apple's [inspector presentation API](https://developer.apple.com/documentation/swiftui/view/inspector(ispresented:content:)).

`RootView` owns the presentation binding and exposes it at the scene level via
`ContextInspectorFocus`. `ReaderCommands` reads that exact binding with
`@FocusedBinding`: **View > Show Context Inspector / Hide Context Inspector**,
shortcut **⌥⌘I**. The toolbar uses the same state and matching Show/Hide labels.
Neither recovery control depends on a loaded source. Scene scope keeps the
command available when source, Files, Search, or inspector controls have focus,
including when the inspector itself is collapsed. No duplicated model state or
AppKit split-view intervention is introduced.

SwiftUI's built-in `InspectorCommands` uses ⌃⌘I, already assigned here to
Repository > Reindex, so this app provides its own scene-bound command without
changing that existing shortcut. See [Apple's command documentation](https://developer.apple.com/documentation/swiftui/inspectorcommands).

Manual acceptance: resize through 220–420 points, drag fully closed, then
restore separately using the toolbar, View menu, and ⌥⌘I. Repeat with source
and file-filter focus, at minimum window width (toolbar overflow), and with
no repository/source open. Each action should toggle once, preserve the source
selection/viewport, and reopen at a usable width. Physical dragging and menu
interaction have not yet been verified for this change.

## Concise default (2026-10-04 refinement; supersedes always-visible detail below)

The user's requests:

- "just show a single line for each, and then have an expansion affordance to
  show more… I want to just be able to eyeball the refs and defs."
- "lose 'under caret', too explainy."

The resulting layout:

- **Declaration region:**
  - One pinned line: icon, **name**, kind, and a trailing line-number link.
    The multiline signature is behind a native `DisclosureGroup` triangle.
  - Each reference or definition is one line: a disclosure chevron, the line
    number, the source line with the match in semibold, and a quiet `def` tag on
    definitions.
  - **Selecting a row no longer shows anything extra.** The automatic
    `ReferencePreviewView` was removed. A row's chevron, or **→/←** on the
    selected row, reveals or hides its ±2-line context in place.
  - ↑/↓ selects, Return or double-click commits, Escape clears the selection.
  - The header keeps the count. A coverage line appears only for "No
    references" or a short caveat ("2 stale · 1 unreadable").
- **Lower region, now titled "Definition"** (or "Outline" on fallback). "Under
  Caret" no longer appears anywhere user-visible.
  - One line shows icon, **name**, a lowercase kind ("function", "local"), and
    a trailing location:
    - a link (`app_image.rs:401`, or just the line number in the same file,
      `+N` for more definitions);
    - `here` on the definition;
    - the external package name (`serde_json`).
  - The triangle, or →/← with the region focused, reveals one line of facts
    (kind · N references · package, or uses in file · enclosing function),
    then the SCIP signature, docs, and the bounded source preview or local
    definition line.
  - Return, Tab-then-Return, the link, ⌃⌘J, ⌘-click, and source Return still
    navigate.
- **Statuses:** every default status is one short line — "File not indexed",
  "No semantic index", "Indexing…", "Not in the index", "References
  unavailable". The full honest reason is in the tooltip and the accessibility
  label (`ContextStatusLine`).
- **Expansion state lives in `ContextModel`:**
  - `isDeclarationExpanded` collapses on a new declaration identity.
  - `isDefinitionExpanded` collapses on a new under-caret identity.
  - `expandedReferenceIDs` clears whenever a reference list reloads.
  - Moving within an identity preserves expansion. The two regions are
    independent. Disclosure never navigates or moves the caret.
  - Everything starts collapsed regardless of window size.
- **Previews are still prefetched** on identity change. This work is
  off-main, cached, and generation-checked, so expanding is instant. No
  multiline text appears until requested.
- **Tests:** `expansionBelongsToIdentityAndStartsCollapsed`. The passive-caret
  navigation test now also toggles every disclosure and selects a row, and
  asserts that navigation state is byte-identical.
- **Gates:** `make check`, **126 tests in 20 suites**, `make build`, strict deep
  codesign, and packaged `--verify-resources` (empty environment, 8 grammars)
  all pass for this refinement. Its first live attempt stopped on native
  `noWindowsAvailable` without retry or workaround. Sol's later visible-caret
  pass confirmed concise default rows and the Definition heading on the
  129-test build. Full disclosure and narrow-width acceptance remain manual;
  see the UI review for exact checks.

## Behavior

The sections below record the initial delivery. Where they describe
always-visible signatures, metadata, or selection-driven previews, the concise
default above supersedes them; that detail now appears on expansion.

### Upper region: Declaration

- **Declaration:** Tree-sitter's innermost declaration around the **genuine
  caret**, using strict half-open byte containment. Nested methods and functions
  resolve to the innermost one. Between the methods of an `impl`, the `impl`
  itself is innermost.
- **Pinned summary:** the summary sits above the list:
  - The name is semibold body text on its own line and may wrap to 2 lines.
  - The kind comes from SCIP when the index has it (Function, Method, Struct…).
    Otherwise it is the Tree-sitter kind.
  - **Line N** is a link that navigates.
  - The signature is real source from the declaration's start up to its body
    fold, capped at 8 lines/600 bytes.
  - The summary has layout priority over the reference list, and the list keeps
    a hard 72 pt minimum. The signature shows its full height when the region
    has room, then steps down to 4, 2, and 1 lines (`ViewThatFits`) only when
    the region is short.
  - Live finding fixed: a greedy high-priority list previously squeezed
    `open`'s multiline signature to one line.
- **Reference preview layout:**
  - The preview also takes layout priority over the list and renders at its
    natural height with no scroll view, since it is at most 5 byte-capped lines.
  - A genuinely short region steps it down to just the reference line.
  - Live finding fixed: an earlier `ViewThatFits` fell back to a zero-minimum
    `ScrollView`, leaving the snippet with no visible height.
  - The hint "Return opens · Esc clears" sits on its own line and may wrap to
    two lines. It leads with Return so it stays recognizable even when
    truncated at narrow widths. Indentation shared with the declaration is removed, so multiline
    signatures read flush.
- **SCIP link:** the region looks for an occurrence at the first byte of the
  declaration's name.
  - A **definition** occurrence links the declaration to that symbol.
  - For an **`impl`**, the real SCIP reference to the implemented type is
    accepted instead, labelled "Implementation."
  - Otherwise there is no link, and the region states honestly why. Typical
    causes are no index, indexing in progress, a file the index doesn't cover,
    or a cfg-inactive item. Nothing is matched by spelling.
- **Ambient references:** loaded automatically and grouped by file, with line
  numbers and the occurrence in semibold.
  - The header count covers **uses only**. Definition hits are listed but
    labelled "definition" and not counted.
  - Unmapped (stale) occurrences and unreadable files are reported.
- **Find References** (⌃⌘R, menu, or source context menu) is still available.
  It switches the region to **References** for that symbol. **Follow Caret**
  returns to ambient mode; the declaration keeps tracking the caret underneath.

### Lower region: Under Caret / Outline

- **Resolution:** the region resolves the real SCIP occurrence at the caret,
  using the existing narrowest-wins `SemanticIndex.target` rules. Import-role
  occurrences are excluded.
- **Metadata, shown immediately:**
  - Name, plus the kind ("Local variable" for locals).
  - The SCIP `signature`, verbatim.
  - The first prose paragraph of the documentation, with code fences skipped.
  - The definition location as a link button. It shows "This file:N" or
    "file.rs:N", plus a count of any extra definitions.
- **Calls and types (non-locals):**
  - A bounded definition preview: at most 12 lines, each capped at 400 bytes.
  - For a definition in the open file, the preview comes from memory, bounded by
    its Tree-sitter declaration.
  - For a definition in another file, the preview is read and parsed off the
    main actor by `SemanticQueryWorker`, using the existing `SyntaxWorker`. The
    excerpt ends with the Tree-sitter declaration whose name holds the
    definition byte, so adjacent items without a blank line are excluded.
    Example: `restore_app` previews `app_image.rs:401–403` and stops before
    `fn restore` at line 404.
  - Parsed destinations are cached per path and content identity (4 entries).
  - Files without a grammar, or with no matching declaration, fall back to
    stopping at the first blank line.
  - Shows the index reference count.
- **Locals** are quiet: the single definition line (when the caret is not on
  it), the SCIP enclosing symbol name, and the number of occurrences in this
  file. There is no async read.
- **External/dependency symbols** (no in-repository definition): the region
  says "Defined in serde_json 1.0.151, outside this repository. Its source is
  not indexed, so there is no preview." The package comes from the SCIP symbol
  header; a version field that is a URL is dropped. Nothing is fabricated.
- **On a definition:** shows "Defined here", or "Defined here and in N other
  places". No redundant preview.
- **Fallback:** on whitespace, keywords, punctuation, imports, or anything
  without a single-line SCIP occurrence, the region becomes the existing
  keyboard-navigable **Outline**. The outline keeps its Up/Down preview and
  Return commit.
- **Availability detail:** beside "Outline", the header shows a truthful detail
  from `SemanticAvailability`:
  - "No semantic index": the repository has no usable index.
  - "Indexing…": no usable index yet, and indexing is running.
  - "File not indexed": a usable Current, Partial, or stale index does not
    cover this file, such as tkos `README.md`.
  - "Loading semantics…": the file's occurrence map is still being built.
  - Nothing at all: the file is covered and the caret is simply on
    whitespace or a keyword.
  - The declaration region's explanation uses the same classification.

## Keyboard and navigation contract

| Action | Effect |
| --- | --- |
| Arrow keys, clicks, find in source | Update context only. No navigation, no scroll change, no history. |
| Scrolling | Updates the restoration `positions` only. Never the caret or either region. |
| Reference list ↑/↓ | Selects a row only (concise default). Source, caret, scroll, and history are untouched. |
| Reference list →/← or row chevron | Reveals or hides that row's ±2-line source context in place, bounded and byte-capped. |
| Definition row triangle, or →/← with the region focused | Reveals or hides the signature, docs, facts, and preview. |
| Return / double-click / **Open** / context-menu "Go to Reference" | Commits: `navigateSemantically(from: caret, to: hit)`. Native list actions commit the row ID they name, not the stored selection. |
| Escape in the reference list | Clears the preview selection. |
| Lower region Tab-focus + Return, the definition link, ⌃⌘J, ⌘-click | Go to definition, recording the caret as the departure. |
| **Return / keypad Enter in the focused source reader** | Goes to the definition of the SCIP symbol at the caret, just past it, or in the selected word. Uses the same semantic path as ⌘-click and records the exact caret as Back's departure. See below. |
| Declaration **Line N** link | `navigateSemantically(from: caret, to: declaration name)`. |
| ⌘[ / ⌘] | Back returns to the **exact caret byte** that was left, not a scroll position. |

## Visible source caret (2026-10-04 refinement)

Because the reader is read-only, it now draws its own subtle steady caret. See
`plans/structural-navigation.md`. Arrow keys move it between several symbols on
one line. The Context regions follow the same genuine caret, and Return/Enter
goes to the definition at it. Nothing about the caret navigates.

After all gates passed with **129 tests in 21 suites**, GPT Sol verified the
caret live on tkos: character-level arrows changed the lower Context row
without navigation, word selection and sidebar focus hid the caret, and pinned
tint did not obscure it. Return/Back still worked. Dark mode and Unicode edge
cases were not exercised live; see [the review](context-ui-review.md) for
screenshots and evidence boundaries.

## Return/Enter in the source reader (2026-10-04 refinement)

The user asked that Return on a call's symbol go to its definition, with ⌘[
returning to where they were. `ReaderTextView.keyDown` handles this as a
narrow AppKit route. It is not a menu key equivalent.

- **When it fires:** only for plain Return (key code 36) or keypad Enter (76).
  It never fires with ⇧, ⌘, ⌥, or ⌃ held, or while text input is marked. The
  view only receives these keys while it is first responder, so the sidebar's
  Return (reference commit, lower-region activation) and the find bar are
  unaffected.
- **Where the target comes from:** only from existing callbacks. The UTF-16
  selection becomes bytes through `byteForUTF16` and is resolved by
  `semanticTarget` (SCIP).
  - A caret inside an occurrence uses that occurrence.
  - A caret immediately after one (arrowed to its end) targets the
    occurrence, while the departure remains the caret.
  - A non-empty selection, such as a double-clicked word, must lie wholly
    inside one occurrence.
- **Navigation:** it fires only when the target has an in-repository
  definition other than the one under the caret (`hasDefinition`).
  - It calls `AppModel.goToDefinition(at:departingFrom:)`, the ⌘-click path.
    Back therefore returns to the exact caret byte, even after passive
    scrolling.
  - It applies to any SCIP symbol with such a definition: calls, types, and
    locals. Navigation always comes from the index.
- **Pass-through:** everything else goes to `super.keyDown`:
  - whitespace;
  - unindexed files, and the cfg-inactive gaps that only the syntactic local
    fallback covers;
  - external or stdlib symbols;
  - the definition itself;
  - over-wide selections.

  The read-only view then does nothing beyond AppKit's normal response. No
  spelling fallback, no guessed target.
- **Untouched:** native selection, copy, double-click pins, ⌘-click, and the
  context menu.
- **Tests:** `ReaderReturnKeyTests`, 2 tests.
  - The first drives the real `keyDown` with synthetic targets. It covers emoji
    and accented text before the call (UTF-16 ≠ UTF-8), the end-of-token caret,
    exact word selection, over-wide selection, all four modifiers, keypad
    Enter, external and on-definition targets, whitespace, and a non-Return
    key.
  - The second wires a real `ReaderTextView` and `SourceViewerCoordinator` to
    an `AppModel` with the fixture index: caret in `item.area()`, passive
    scroll, Return to `shapes.rs:7`, ⌘[ to the exact caret, and Forward. Return
    on the `total_area` definition does not navigate.
  - Removing the modifier or selection-bound guards produced 5 failures.

## Architecture and decisions

- **Genuine caret.** `AppModel.caretLocation` is set only by
  `SourceViewerCoordinator.textViewDidChangeSelection`, through
  `AppModel.caretMoved`, and by navigation that places the selection.
  `positions` still mixes caret and viewport top for file restoration and
  history, and is no longer used as the caret. `currentCaretLocation`,
  Go to Definition/Find References at caret, and every sidebar commit use the
  caret.
- **Identity keys, no debounce.**
  - The declaration identity is path, declaration id, source content identity,
    linked SCIP symbol, and index revision.
  - The under-caret identity is path, source identity, symbol, occurrence byte
    range, index revision, and document-map revision.
  - `ContextModel.update` recomputes the identities. This costs one linear pass
    over the file's declarations and one binary search of the occurrence map.
    It writes observable state only when an identity changes.
  - `SemanticModel.caretMoved` likewise writes `caretTarget` only on change.
  - Arrowing through `Value` or `as_object` therefore causes no rebuild, no
    fetch, and no view invalidation. Counters prove this in the tests.
- **Independence.** Each region view observes only its own `ContextModel`
  properties. The reference list's selection and scroll survive any number of
  under-caret changes.
- **Off-main work.**
  - References and cross-file previews use **separate** `SemanticQueryWorker`
    actors, so a long reference scan never queues a preview behind it.
  - Every task carries a generation UUID and is cancelled when its identity
    changes. File, repository, and index changes and `reset()` invalidate
    everything.
- **Caches.**
  - Reference results are cached by symbol (24 entries) and previews by
    definition position (64), both bounded.
  - Both are cleared on index replacement, repository change, and when **new
    bytes appear at a path that was opened before**, even if the index object is
    the same.
  - A same-symbol declaration update keeps loaded references only when the
    index revision *and* source identity are unchanged.
- **Change hook.** `SemanticModel.onDocumentChange` notifies `AppModel` when the
  index or the open file's occurrence map changes, so context re-keys without
  polling. `AppModel` also refreshes after source loads, syntax arrival, and
  same-file navigation.
- **Bounded text.**
  - `SourceBuffer.displayLineText` caps a line at 400 bytes on a scalar
    boundary.
  - Reference rows window very long lines around the match: a leading "…",
    with the match always visible.
- **SCIP name fix.** `SCIPSymbolString.fallbackName` now honors backticks
  inside `[...]` descriptors. Real core symbols such as
  ``slice/impl#[`[T]`]first().`` previously displayed as `]first().`.

## Typography and design

The type choices follow the typography-designer and macos-design skills, using
system semantic styles only:

- **Region labels:** subheadline semibold, secondary.
- **Symbol names:** body semibold, the one emphasized element per region.
- **Metadata, counts, status, and hints:** callout regular, secondary or
  tertiary.
- **Signatures, reference rows, and snippets:** callout monospaced. The match or
  emphasized line uses callout monospaced semibold.
- **Snippet line numbers:** caption tabular digits, tertiary.

Snippets sit on the text background color with a 6 pt rounded separator stroke.
They are selectable, and VoiceOver reads the numbered source lines as the
element value. A quiet visible hint, "Return opens · Esc clears", makes keyboard
exploration discoverable. The toolbar control is now **Toggle Context**.

## Validation (this round)

- **Repair pass after Sol's first live review** (findings in
  `plans/context-ui-review.md`, owned by Sol):
  - Fixed all four defects: the squeezed pinned signature, the zero-height
    reference snippet, the adjacent-declaration preview spill, and the
    misleading "No semantic index" on an unindexed file in an indexed
    repository.
  - Final gates after the repairs, on SHEFFIELD (macOS 26.5, Swift 6.3.3): see
    the last bullet of this list.
  - New tests:
    - `availabilityDistinguishesRepositoryIndexFromFileCoverage` (Current,
      Partial, Possibly Stale, and reindex-with-index states);
    - `unindexedFileInAnIndexedRepositoryIsLabelledByFileCoverage` (an
      unindexed `Cargo.toml` next to indexed sources, then a repository with
      no index).
  - New: an adjacent-declaration preview regression, and the fixture preview
    of `area` bounded to lines 7–10.
  - Mutation check: reverting to the blank-line bound failed both.
  - Fixed the reference preview's zero-height snippet and the squeezed pinned
    signature. These are layout-only changes with no unit test; they await
    Sol's live recheck.
  - Fixed a **pre-existing test race** in
    `SemanticNavigationTests.switchingRepositoriesDropsTheOldIndexAndTargets`.
    The test waited for `.noIndex`, which `repositoryOpened` sets synchronously
    as a "Checking the repository…" placeholder. It now waits for the service's
    real publication. The race was seen once in a full run before the fix;
    three consecutive full runs passed after it.
  - **Final gates after the repairs:**
    - `make check` passes.
    - `make test` passes **123 tests in 19 suites**.
    - `make build` replaced the signed `build/Radiology.app`.
    - `codesign --verify --deep --strict` passes.
    - `--verify-resources` passes from `/tmp` with an empty environment (8
      grammars).
    - Live recheck of the repaired build is Sol's.
- **Initial delivery:**
  - `make check`: pass.
  - `make test`: **120 tests in 19 suites**, all pass. The baseline was 97/16.
    The opt-in probes are no-ops without their environment variables.
  - `make build`: pass.
  - `codesign --verify --deep --strict build/Radiology.app`: pass.
  - `--verify-resources` from `/tmp` with an empty environment: all 8 grammars
    pass.
- **New suites:**
  - `ContextModelTests` (17 tests after the repair pass) covers:
    - within-token and within-declaration stability, with counters;
    - selection retention while under-caret changes;
    - impl linking, whitespace/keyword/no-structure fallback, and locals;
    - external-symbol honesty;
    - stale async results;
    - reset and root change, and a new index revision;
    - same-index/new-bytes cache invalidation;
    - explicit references and Follow Caret;
    - a synthetic UTF-16 index with emoji and `café`, including a surrogate-pair
      split;
    - long-line windowing on scalar boundaries;
    - escaped SCIP descriptors;
    - flush nested multiline signatures.
  - `ContextNavigationTests` (8 tests after the repair pass) covers:
    - passive caret movement leaving navigation state byte-identical;
    - scroll never moving the declaration;
    - reference preview vs commit, with Back/Forward to the exact caret;
    - native actions committing the named row;
    - every sidebar definition entry point recording the caret, not the
      viewport;
    - file and repository resets with structure-only browsing;
    - an AppKit test that selection changes report the caret (correct after an
      emoji) while scrolling does not.
- **Mutation checks:**
  - Making `currentCaretLocation` prefer `positions` failed 3 navigation tests.
  - Removing the under-caret identity guard failed 2 model tests.
- **Real data:** `ContextRealDataProbe` is opt-in, enabled by setting
  `RADIOLOGY_CONTEXT_PROBE` to the tkos cache directory. It resolves Sol's
  cases against the existing app-owned cache
  `~/Library/Caches/Radiology/repositories/98b359c61dd73dfb`, generated
  2026-10-04 at tkos `239b9f6d4`. tkos was only read.

### Real tkos results (cache above; counts are this cache's, not universal)

- `engine/rust/src/app_image.rs`:
  - **Lines 93–100:** declaration `section` [Function], with 3 references at
    lines 413, 420, and 424, plus the definition line 93.
    - `input` is a Parameter local (definition 93, 5 occurrences in the file).
    - `prefix` is a local (definition 94, 2 occurrences).
    - `length` is a local (definition 95, 3 occurrences).
    - `bytes` is a local (definition 96, 2 occurrences).
    - The enclosing name is `section`.
    - Indentation falls back to the Outline.
  - **Lines 413/420/424:** the caret on `section` previews 9 lines from line 93.
    The declaration there is `restore` (line 404, 2 references at 399/402).
  - **Line 401:** `restore_app` has 2 references, at `runtime.rs:145` and
    `runtime.rs:276`.
  - **`PreparedApp` on line 401:** defined at line 50, 10 references,
    previewing `pub struct PreparedApp(Restored);`. `PreparedBase` on line 398
    is defined at line 48, with 6 references.
  - **Lines 19–27:** `android_log` and the Android-only functions have **no
    SCIP symbol** (cfg-inactive under the indexed configuration). The
    declaration shows its signature with the honest unavailable explanation.
    Under-caret falls back to the Outline.
- `engine/rust/src/runtime.rs:145`: the caret on `restore_app` shows the
  definition at `app_image.rs:401`. After the repair pass, its preview is
  exactly lines 401–403 (initially it ran on into `fn restore`).
  The enclosing declaration is `Java_inc_tk_os_engine_NativeRuntime_run`
  (line 106, multiline JNI signature, 0 references, 1 definition).
- `modules/agent/ffi/src/app.rs`:
  - **Line 1343:** the declaration is `open` [Method]. Its 7-line multiline
    signature reads flush. It has 4 references (lines 343, 763, 895, 1064).
  - **Line 1352:** `Value` (1,684 index references) and `as_object` (35) are
    external to serde_json 1.0.151, so there is no preview.
  - **Line 1351:** `first` is shown as an external from core.
  - **Lines 4283–4288:** the test
    `transcript_bridge_matches_the_shared_typescript_fixture` (declaration line
    4243) contains a comment with "—" at line 4286. `read_observation` at line
    4288 previews `app.rs:2058` (truncated at 12 lines).

## Limitations

- No filesystem watcher. A file changed on disk is noticed when it is reloaded
  or reopened. Cross-file previews and reference snippets of *other* files
  refresh on reload (⌘R), on an index change, or after a source-identity change
  of an opened file.
- A cross-file preview is still capped at 12 lines, with "…" when the
  declaration is longer.
- Import fallback depends on the indexer setting the SCIP import role.
  rust-analyzer does not always set it, so a `use` path may show its target
  symbol instead of the Outline. This is truthful, but less quiet than
  requested.
- Methods resolved through std/core traits (`.first()`, `.unwrap()`) are
  externals without previews. Stdlib sources are never fabricated.
- The engine crate remains **source-only/no-deps** (`deno_core` vendor inputs
  absent). Coverage gaps there, such as `snapshot_profiles_test.rs`, are
  reported, not hidden.
- Tests, implementations, and overrides enrichment are out of scope.
- **Live evidence:** Sol verified narrow widths, split behavior, visible focus,
  lower-region Tab/Return, navigation/Back, and the three visual repairs.
  Native capture failed before the final README label check; open README.md
  and screenshot **File not indexed** with **Index Partial**. VoiceOver speech,
  dark mode, Cmd-click, contextual row activation, and long-list scroll
  retention remain unverified. See the UI review for exact evidence limits.
