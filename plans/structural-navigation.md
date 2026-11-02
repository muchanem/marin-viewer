# Structural navigation

**Current-function keyboard fold, 2026-10-11:** plain x in the focused source
reader toggles its innermost named function's existing body fold. Folded ancestors
open when needed to reveal an expansion; unrelated fold state and the exact caret
remain. See [function-fold-key.md](function-fold-key.md).

Radiology's Tree-sitter structure is a coordinated reading surface. All
locations remain canonical UTF-8 byte offsets; TextKit conversion still occurs
only through `SourceBuffer`.

## Outline and synchronization

The outline now appears in the Context inspector's lower region whenever no
semantic symbol is under the caret (plans/context-sidebar.md); its current behavior
is described below. Breadcrumbs and outline highlighting still follow the
`positions` restoration point, while the Context regions follow the genuine
caret only.

The sidebar surfaces every callable declaration (including methods, initializers,
deinitializers and nested functions) in a flat first group, largest to smallest
by inclusive signature-to-end source line span. Half-open byte ranges use the
last included byte for the ending line. Ties retain source order. Original
Tree-sitter IDs and selection ranges are used for navigation. Remaining
non-callable declarations follow in a native Declarations hierarchy; callable
containers are removed from that hierarchy, with their non-callable descendants
promoted to the nearest remaining container. Functions are never duplicated.
This sidebar ordering is identical in Normal/Critical and does not change
source-order context, breadcrumbs, graph sites or gutter behavior. Cached outline
refresh is keyed by source path, syntax path, content identity and symbols, so
identical-content file switches cannot strand an old cached outline.

Clicking an outline row commits a history entry and selects its declaration.
Native Up/Down movement previews without changing selection or history; Return
commits. Passive source scrolling updates the enclosing declaration and
breadcrumb. A programmatic jump reports its target before ordinary scroll
synchronization resumes, preventing viewport clamping near EOF from replacing
the intended selection.

Pointer activation is independent of the list's selection-change callback, so
clicking an already-selected row still issues a fresh jump. Preview ignores the
exact committed target instead of racing it. Before scrolling, every manual or
definition fold containing the destination is removed. A revision-guarded second
layout pass on the next main-actor turn positions the source after TextKit has
settled changed fold and font geometry; a superseding navigation cancels it.

Outline pointer jumps briefly paint the complete destination line with the
dynamic system accent color at low alpha. This is a `ReaderTextView` background
presentation only: it does not modify attributed source, syntax colors,
selection, copy/find ranges, or canonical bytes. Repeated clicks restart the
feedback. Any new navigation or file clears it. It holds for roughly 650 ms and
then fades over roughly 200 ms; Reduce Motion clears it without the fade.

## Breadcrumbs and history

The header displays repository / relative path / enclosing declarations.
Its leading breadcrumb retains nearby directories and declaration ancestors
as space allows, dropping far path entries first. File/final declaration take
priority; full location/all declaration jumps remain in the ellipsis menu.
Change/collapse controls retain a compact trailing area; Before/After is now beside source mode in the main toolbar. See
[source breadcrumb layout](source-breadcrumbs.md) for measurements and evidence.
Declaration components are buttons. History distinguishes a file-opening
restoration position from a pinned structural anchor. Preview and passive
synchronization never append entries; Back/Forward do not duplicate entries.

## Current-function shade

A barely-there background marks the function the reader is in, so it can be
noticed when looked for.

- **Which function:** the innermost Tree-sitter `function`, `method`,
  `initializer`, or `deinitializer` symbol containing the **genuine caret**
  (`SyntaxSnapshot.innermostFunction(at:)`), from its signature through its
  body.
  - Types, `impl` blocks, modules, and properties never qualify. Between
    methods there is no shade.
  - Anonymous closures are not symbols, so their owning named function stays
    shaded. A nested named `fn` is shaded on its own.
  - No brace scanning is involved.
- **State:** `AppModel.currentFunctionRange` is recomputed in the existing
  `refreshContext()` path and written only on change. There is no debounce
  and no timer.
  - Passive scrolling never changes it, because it follows the caret and not
    `positions`.
  - It clears immediately on a file change, on repository open, when outside
    any function, and while structure is unavailable or unsupported.
- **Drawing:** `ReaderTextView` paints full-width bands from TextKit line
  fragments, first in `drawBackground`. It sits beneath the current-line tint,
  occurrence and pin decorations, and the caret, which all stay legible.
  - Only the visible slice of the function is mapped to glyphs. The visible
    glyph range is intersected in character space before mapping back, so a
    very long function never forces glyph generation or layout past the
    viewport.
  - A folded body contributes no height: its null glyphs share the surviving
    `{…}` line.
  - A change of function repaints the visible source once. Moving the caret
    within a function changes nothing.
- **Color:** `labelColor` at 3% opacity in light mode and 4.5% in dark. It is
  neutral under any accent and lighter than the accent-tinted current line.
- **Tests:** `FunctionShadeTests` (3):
  - Rust nesting, closures, `impl` and struct exclusion, the half-open end,
    and Python nesting.
  - Caret versus scroll, file, repository, and missing-structure clearing.
    This caught a real bug: the shade was not cleared on repository open.
  - TextKit band bounds, viewport clipping, fold collapse, and stale ranges.

GPT Sol verified this live in light mode on tkos after the 132-test signed
build: faint whole-function extent, outside-function clearing, adjacent
boundaries, fold collapse/expansion, passive-scroll stability, and legible
highlight/caret layering. Dark appearance was not exercised. Screenshots and
exact observations are in [the UI review](context-ui-review.md).

## Read-only source caret

The reader is read-only (`isEditable = false`), so AppKit draws no insertion
point, and editing is deliberately not enabled to get one. Instead,
`ReaderTextView` draws a subtle caret: a 1.5 pt steady bar in
`NSColor.textInsertionPointColor` at 85% opacity, so readers can arrow
between several symbols on one line without a mouse.

- **Geometry:** from TextKit's laid-out glyphs at the selection's UTF-16
  boundary, never from character-width multiplication.
  - Glyph location on the line fragment gives x and the baseline. Height spans
    the font's ascender to descender.
  - Tabs, emoji, ZWJ, and combining sequences are handled. The caret snaps to
    the start of a composed character, because trailing UTF-16 units carry null
    placeholder glyphs.
  - End of line, and EOF after a final newline (the empty last line) or after
    a final grapheme cluster (its complete glyph span), are handled.
  - Inside folded text, where glyphs carry `.null`, there is no caret.
- **Gating:** shown only when the reader is first responder in the key window
  and the native selection is empty. A highlighted range is its own cue.
  Window key changes and responder changes repaint only the caret strip.
- **Drawing:** painted last in `drawBackground`, above the current-line tint
  and occurrence/pin decorations.
  - Selection changes already repaint the visible source for the line tint, so
    there are no timers and no stored positions to go stale after folds or
    font changes.
  - Overriding `draw(_:)` was tried and rejected: it measurably changed
    NSTextView's scroll-restoration behavior in
    `aFreshDocumentJumpSizesTheWholeFileBeforeRestoringPosition`.
- **Unchanged:** canonical bytes, selection, copy, pins, folds, Context, and
  Return-to-definition.
- **Tests:** `SourceCaretTests` (3).
  - Geometry, including EOF after `🚀`, `x👨‍👩‍👧`, and `xe\u{301}` without a
    trailing newline. Reverting to the pre-fix EOF code failed these.
  - Fold rejection.
  - The real focus/selection gate, using a test window that reports itself key
    (headless runs never grant key status). Removing the gate failed 2
    expectations.

## Default function folding and Fold to Definitions

For local checkout, as soon as structure arrives for a newly loaded supported source, Radiology
collapses every captured function implementation body once. Type, class, impl,
protocol, interface, module, and other declaration containers remain open, so
the initial view is a scan of signatures rather than a sequence of adjacent
implementations. The one-time state belongs to the loaded buffer: repainting,
resizing, changing source type size, or receiving another SwiftUI update does
not undo a user's manual expansion.

**PR initial exception:** ordinary folds intersecting changed line ranges or
containing conservative empty-side insertion points are expanded once matching
syntax and exact-review/path/revision/content hunks are ready, in either async
order. Enclosing ancestors open too. Whole function/closure scopes identify
signature-to-body ownership, with `FoldHeaderOwnership` capturing actual Rust
attribute siblings and Python decorated definitions; lexical/semantic scopes do
not change. An edit to one header does not open sibling closures. Changed added/
removed functions use After/Before ranges; pure empty sides do not invent washes.
EOF inside an unfinished/indentation body is owned; outside a closed braced body
is not evidence its neighbor changed.

`ReviewFoldInput` selects fold IDs; coordinator applies once before the combined
layout. Manual touched folds and bulk commands made while hunks are pending win.
New coordinators adopt existing command counters instead of replaying another
file's old command. New document/revision/review/content resets initial defaults;
index/appearance/filter/caret changes do not. Hide Tests remains an independent
hidden-range union and is not revealed by automatic ordinary-fold expansion.

Late fold/syntax layout retains the viewport's source row and selection, not
an old navigation target. Restoration cancels deferred old navigation/position
markers and suppresses scroll-position callbacks; newer explicit navigation
clears a pending restore and wins. Explicit navigation still reveals its target.
Source bytes, semantic coordinates, caret and history are unchanged by defaults.

The header has an always-visible **Collapse Functions** control (disabled when
the file has no function folds) with a tooltip and accessibility label. The
same action is available from the app menu with `⌘⇧0`; it adds all function
folds back without disturbing manual non-function folds, navigation history, or
source bytes. When syntax arrives after a requested jump, default folds are
applied first and the target is revealed afterward, so asynchronous parsing
cannot hide the destination.

Navigate > Fold to Definitions (`⌘⌥0`) collapses function bodies and leaf type
bodies. Containers with nested declarations remain open, so method signatures
stay visible. Rust `extern C` signatures remain visible. Navigation removes any
fold that actually hides its target. Manual folds, copy, find, and coordinates
continue to use unchanged backing text.

The separate `LineNumberGutter` enumerates surviving TextKit line fragments and
maps the first real glyph in each fragment back to its canonical source line.
Hidden glyph aliases therefore cannot stack or mislabel rows. Fold controls use
an 11-point medium disclosure glyph centered in a 28-point-wide, full-line hit
target, with pointing-hand cursor and accessibility help.

A collapsed function has a three-point secondary-label meter whose logarithmic
width is `6 + 10 × log2(hiddenLines + 1) / log2(257)` points (capped at 256),
plus a neutral capsule with the hidden-line count where space permits. The
72-point gutter uses a 20-point disclosure/meter lane and sparse canonical
numbers (multiples of five plus the actual native caret). Count badges use spare
space and defer to tooltip/accessibility when they cannot fit beside a number;
see plans/source-gutter.md. Numbers remain small UI metadata at all source zooms. Counts
come from canonical source boundaries and are independent of font/layout.
Tooltip and accessibility help report “Collapsed function — N lines hidden.”
Expanded and non-function folds have no cue.

Fold glyph ranges are normalized to disjoint outermost ranges, so a nested
function cannot paint a marker through a collapsed parent. Null glyphs retain
their original TextKit properties while hidden control characters use zero
advancement. This keeps large bodies compact without corrupting the glyph to
character map. Delegate detachment is limited to source replacement, and one
SwiftUI update never generates the same large folded layout twice.

### Large-file performance

The effective folded ranges are cached in sorted, disjoint UTF-16 form at the
TextKit boundary. Per-glyph and per-control-character membership uses binary
search. A fold update diffs old and new effective ranges: an invisible nested
change is a no-op, changed glyph properties are regenerated only for their
union, and layout is invalidated from the earliest changed character to EOF
because downstream vertical positions move. This preserves canonical source
coordinates while avoiding a whole-document glyph regeneration on every click.
The real tkos 4,880-line `app.rs` rendered-completion probe covers large,
medium, and tiny folds and explicitly forces layout after each toggle.
It is opt-in through `RADIOLOGY_REAL_FOLD_BENCHMARK=1` because it reads the
untouched external tkos checkout; normal portable tests retain the generated
607-row multiline/nested-function regression fixture.

## Hidden test code (Hide Tests)

Test regions detected by `TestRegionDetector` (plans/source-filters.md) are
hidden through the same fold machinery. While Hide Tests is on, each hidden
region contributes its post-header UTF-16 range to the fold union. Folds and
test ranges are merged into one sorted disjoint set; overlapping ranges now
merge rather than coexist. The header line stays visible and recedes at draw
time, merged with any Critical Lens receded ranges.

- **Gutter:** on the header row, ▶ and the standard hidden-line capsule take
  precedence over a fold control on the same row. The tooltip reads “Test code
  — N lines hidden. Click to show.”
- **Reader:** draws a quiet clickable label after the header text.
- **Navigation:** reveals the target's test region in the model before the
  viewer's own fold reveal and scroll, in one combined layout pass.
- **Folds:** fold IDs are untouched, so manual and default folds survive
  toggling. Covered by `TestCodePresentationTests`.

## Language limits

Function folding follows existing grammar captures. Swift function and
initializer bodies; Rust functions and block-bodied closures; Go functions,
methods, and block-bodied function literals; Python sync/async function bodies;
JavaScript/JSX/TypeScript/TSX declarations, methods, function expressions, and
block-bodied arrows; and Kotlin function bodies and lambdas are included.
Brace bodies retain delimiters; Python indentation blocks collapse whole.
Expression-bodied arrows/functions have no implementation block to hide and
remain visible. Rust `extern` declarations have signatures but no bodies, so
they also remain visible. Go interfaces/grouped declarations and JSX elements
still lack fold captures. Indentation-delimited fold controls are anchored to
the preceding visible signature line rather than the hidden first body line.
Breadcrumbs and outline symbols are syntactic, not semantic.
