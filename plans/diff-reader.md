# Diff reader

The diff reader is the Marin viewer's main column: a PR's changes read either
step by step along its code path (By step) or file by file (By file). It
renders the demo's `#main` for a real PR from a Marin clone and a wordbase
fixture. Code lives in `Sources/Radiology/Viewer/Diff/`, tests in
`Tests/RadiologyTests/Viewer/`. The pure parts (diff parsing, visibility,
excerpt rows, chips, notes, blame parsing) are in the `ViewerCore` package.

## Data

`PRReviewLoader` (an actor, so all of it runs off the main thread) builds a
`PRReviewDocument` from a PR directory (`wordbase/prs/<n>/`) and a git
checkout:

- one `git diff -M -U1000000 base head` for the whole PR, parsed by
  `ViewerCore.UnifiedDiff`, so every file diff carries every line of the file
  and the reader decides what to hide;
- `git show head:path` (and `base:path` for files with deletions), parsed by
  Radiology's `SyntaxWorker` into per-line highlight runs and declarations;
- steps from `code-path.json`, with each excerpt resolved by its `functions`
  against the head's declarations (the union of their spans, decorators
  included) and its `lines` used only when no name resolves. An excerpt that
  resolves by neither carries a `problem` string shown as the "lines a to b"
  tooltip;
- file descriptions from `files.json`, else the wordbase entry at
  `wordbase/<path>.md`; notes from `notes.jsonl`.

Resolved spans for #10640 differ from `code-path.json` by trailing blank lines
and leading decorators, and step 5's first excerpt widens to the union of
`BRIDGE_SOURCE` and `DaytonaProcessSession` (25 to 160). The loader test
prints every difference.

`BlameStore` (an actor) runs `git blame --porcelain commit -- path` once per
file and commit, shares a run between concurrent callers, and counts runs so
tests can check the cache. Blame loads only for the cards on screen and only
while the Blame toggle is on.

## Rendering

The reader is SwiftUI on the outside and one TextKit view per card body:

- `DiffReaderView` is a `ScrollView` holding a `LazyVStack` with section
  headers kept at the top while their card scrolls (`pinnedViews`). Each card
  is one section: a SwiftUI `DiffFileHeader` and a `DiffCardBody`.
- `DiffCardBody` wraps an AppKit view with two parts: `DiffGutterView` (blame,
  old and new numbers, `+`/`−` or a note dot) and `DiffCodeTextView` (a TextKit
  1 `NSTextView` inside a scroll view that moves only sideways and passes
  vertical scrolling to the reader).
- `DiffCardLayout` gives every display line a fixed top and height (code rows
  one line, gap bars 25 points, notes their wrapped height). The text view sets
  each paragraph to exactly that height and the gutter draws from the same
  numbers, so the two columns cannot drift.
- Gap bars and open notes are empty paragraphs in the text, drawn in
  `drawBackground`; their buttons are hit rects, so selection runs straight
  across them and copying skips them.

Why this split: a single text view per card gives native selection across
rows, ⌘C, Find and accessibility for free, and only the visible part of a long
card is laid out and drawn. A SwiftUI row per line would have needed custom
selection; one text view for the whole reader would have lost the per-card
headers and sideways scrolling. Highlighting reuses Radiology's tree-sitter
queries and `Theme.SyntaxColors`, so the reader matches Radiology's source
view and not the demo's palette.

Since macOS 14 a view may draw outside its bounds (`clipsToBounds` is false by
default). The gutter fills only its own bounds and the card body clips; without
that the gutter painted over the code in offscreen renders.

## Behaviour

- **By step:** kicker "STEP N OF M", title, the step's layered summary (More,
  Full description, Less), then one card per excerpt and a "Next: title" link.
  Excerpt cards show the excerpt plus 3 lines of context; the hidden part is a
  gap bar "N hidden lines at the top, M changed" with Show 15 above, Show 15
  below and Show all. Deletion runs next to an excerpt edge are shown.
- **By file:** source files, then tests, then other paths, each a card with
  every change and 3 lines of context.
- **Card header:** chevron collapses the card; directory in the muted colour and
  file name in ink; the file's one-sentence change description with an inline
  More; "lines a to b" in By step; `+a −d`; Whole file / Diff only.
- **Rows:** deletions in red with old numbers, additions in green with new
  numbers, highlighted from the base and head parses respectively.
- **Blame:** a 156-point column with short SHA, first name and age on the first
  row of each run (and after every gap); the tooltip is the commit summary.
- **Notes:** a dot replaces the `+`/`−` marker: amber for drafts, blue for the
  user's posted notes, grey once resolved. Clicking a dot opens the note card
  under its row and tints the row; clicking again closes it.
- **Context menu on code:** Go to Definition of X, Open Definition in New
  Window, Ask About Selection (⌘>), Ask About X, Ask About Line N, Show or Hide
  Blame, Copy. ⌘-click goes to the definition. On a header: Ask About This
  File, Open File in New Window, Show Whole File. On the step header: Ask About
  This Step.
- **Copy:** only code rows are copied, deleted lines included as text, gaps and
  notes skipped.

## Public API

```swift
let document = try await PRReviewLoader().load(prDirectory: prURL, repository: marinURL)
let model = DiffReaderModel(document: document)   // @Observable @MainActor
model.mode = .byStep            // or .byFile
model.focus(step: 6)
model.reveal(path: "lib/shellbox/src/shellbox/http_service.py", line: 133)
model.showBlame = true
model.focus(note: "f1")         // opens the note, switching to By file if needed
model.onAsk = { chip in ... }                       // ViewerCore.Chip
model.onGoToDefinition = { request in ... }         // DiffDefinitionRequest
model.onOpenInNewWindow = { target in ... }         // DiffCodeTarget
model.onNoteSelected = { note in ... }
model.definitionLookup = { symbol, origin in ... }  // optional, e.g. SCIP
DiffReaderView(model: model)
DiffReaderControls(model: model)                    // By step / By file and Blame for a toolbar
```

The reader keeps no sessions and opens no windows. Asking builds a chip and
calls `onAsk`. Go to definition calls `onGoToDefinition` when set and otherwise
reveals the definition in place: in the current step if an excerpt holds the
line, else in its file's By file card. `reveal(path:line:)` follows the same
rule and flashes the row.

## Tests

- `PRReviewLoaderTests`: the #10640 document (30 files, 8 steps, 5 notes),
  highlights, excerpt resolution, By file order, definitions, blame cache.
- `DiffCardRowsTests`, `DiffReaderModelTests`: display lines, note placement,
  blame runs, layout heights, identifiers, steps, gaps and expanders, reveal,
  notes, chips, go to definition, blame loading.
- `DiffReaderSnapshotTests`: hosts the reader in an `NSHostingView` in a
  window, captures it with `cacheDisplay` and checks the code area is not
  blank. Set `DIFF_READER_SNAPSHOT_DIR` to keep the PNGs (steps 1, 6 and 7;
  By file on `http_service.py` with blame; note f1 open).

Tests that need #10640 find `marin/` and `wordbase/` by walking up from the
test file and are skipped when either is missing.

## Known differences from the demo

- Syntax colours and the code font follow Radiology (SF Mono, `Theme`), so
  there are no ligatures and decorators and strings take Radiology's colours.
- The old-number column is always present; the demo hides it because its
  `--blame-w` variable is never set, which also hides blame.
- Excerpts start at decorators (step 1 starts at line 44, the demo at 45).
- Gap labels say "hidden" and count changes they hide (ViewerCore change
  d6de5b8); the demo says "unchanged" even when the gap holds additions.
- An open note wraps to the visible width; the demo's note runs past the card.
- The noted row is tinted amber with a bar while its note is open.
