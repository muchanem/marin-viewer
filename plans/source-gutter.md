# Compact source gutter and sparse line numbers

Requested 2026-10-08 while toolbar review was underway: narrow the source
gutter, show every fifth canonical source line plus the caret line, and stop
printing every line number. The preceding toolbar edits did not change gutter
width: 104 points was already the committed baseline.

## Rendering contract

- `Theme.gutterWidth` is **72 points** (previously 104); disclosure hit lane
  **20 points**, right inset **6 points**. TextKit's source coordinates are
  unchanged; SourceContainerView gives the recovered width to the scroll view.
- Visible canonical lines are numbered only at multiples of five, or when
  they contain the actual native selection/caret. No special line1 exception.
  The initial caret on line1 naturally shows1. Wrapped fragments do not repeat
  numbers; folded/null glyphs stay unnumbered.
- `LineNumberGutter.currentLine` derives from NSTextView.selectedRange converted
  through SourceBuffer UTF16/UTF8 boundaries. It is not a stored viewport or
  navigation-restoration line. Selection and scroll callbacks repaint without
  duplicating caret state. Passive scrolling cannot change the emphasized line.
- Typography uses native SF monospaced digits at `NSFont.smallSystemFontSize`
  (11 points here), independent of source zoom: regular/secondary for fifth
  lines, medium/primary for the caret. Numbers stay centered in the source's
  actual row height. Source fonts/line heights remain.
- Fold/test disclosure, Critical annotations and PR change bars remain for
  every relevant visible row, regardless of whether its number is printed.
  Count badges use remaining width; if they cannot fit beside a canonical
  number, exact counts stay in existing tooltip/accessibility text. No overlap
  or wider gutter is introduced. The logarithmic function meter fits the
  smaller disclosure lane (6–16 points; saturation at256 hidden lines).
- Accessibility reports the current line and sparse-number cadence. Cached
  `numberedLines` records actual draw results for native rendering verification.

## Evidence

Native TextKit/NSView rendering tests, with real glyph fragments and bitmap
draws, prove `[1,5,10,15,20]` with the initial caret, then `[5,7,10,15,20]` after
moving to line7. Scrolling the viewport past that caret preserves7 while its
offscreen label disappears. Folding removes line10's label; reopening restores
the original canonical number, with caret18 still emphasized. The tests also
verify the 72-point frame and scroll/gutter adjacency. Both tests pass.

The separately signed native review instance opened actual PR758 ContactsModule
in light appearance. Go to Line7 showed7 as the sole non-fifth number among
10/15/20/25/30/35. Down moved the caret to8:7 disappeared,8 appeared, fifth
labels stayed. The 72-point gutter and unchanged source font were observed.
[Caret7 screenshot](/Users/tqbf/codebase/radiology/build/toolbar-review/compact-gutter-caret7.jpeg),
[caret8 screenshot](/Users/tqbf/codebase/radiology/build/toolbar-review/compact-gutter-caret8.jpeg).
Native fold/scroll behavior is proven by the bitmap tests; physical fold clicks,
dark appearance and very large-number/count combinations remain unverified.

Applied swiftui-pro before/after decisions, macos-design, typography-designer.
Source bytes, offsets, folding membership, reference/navigation and histories
are preserved. Combined final gates: **246 tests / 51 suites**, check/build,
strict deep signing, empty-environment packaged resources and diff check pass.
Signed **2026-10-08 16:10:23 CDT**. See plans/toolbar-layout.md for toolbar review
and the bounded native-resize limitation. No user app was operated/restarted.
