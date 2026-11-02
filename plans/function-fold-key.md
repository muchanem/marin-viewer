# Toggle the current function with x

Implemented 2026-10-11. Plain **x**, with the read-only source reader focused,
expands or collapses the innermost named function/method/initializer at the
native selection's start. It uses Tree-sitter only, including in Before and
unindexed source. Outside a foldable function it leaves fold state unchanged.
Abstract and single-line bodies have no existing body fold and remain unchanged.

## Routing and state

`ReaderTextView.keyDown` recognizes an unmodified x (Caps Lock allowed), converts
the selected UTF-16 location through the owning buffer, and invokes the viewer's
weak coordinator callback. Command/Option/Control/Shift combinations, marked
text composition and editable text do not take this route. There is no global
alphabetic shortcut, so find/search/picker/sidebar controls retain their own
input handling. Holding x consumes repeat events without repeatedly toggling.
Return/Enter definition navigation remains its existing separate route.

`SyntaxSnapshot.enclosingFunctionFold(at:)` reuses `innermostFunction` and matches
the declaration's own function-body fold by its name/start and exact declaration
end. It never substitutes a nested function, default-argument lambda, unrelated
block or enclosing type when that body cannot fold. Multiline signatures are
included in the declaration's caret range; ranges remain half-open.

`SourceViewerCoordinator.toggleFunction(at:)` uses its existing fold IDs. A
collapsed own body expands; an open body collapses. If folded ancestors hide the
function, the action expands it and those ancestors so the change is visible,
while sibling/nested fold choices remain. Manual decisions are recorded through
the same mechanism as gutter toggles, protecting them against late PR defaults.
The common `setFold` path applies the existing disjoint TextKit glyph projection
once and refreshes the gutter. No source bytes, selection, history, filters,
mode or semantic state are changed; a caret in hidden body text retains its
canonical position and can press x again to restore the body.

The source accessibility help and README shortcut table describe the action.
No typography or layout changes. Applied swiftui-pro before decisions and in
the final review, plus macos-design keyboard interaction guidance.

## Verification

Four new tests drive real ReaderTextView keyDown events and the existing TextKit
fold projection: collapse/expand, nested callable targeting, unchanged selection/
source and absent caret notifications, actual hidden/visible glyph caret geometry,
ancestor expansion, sibling/closure fold retention, outside/no-syntax behavior,
Caps Lock, modifier and editable-field gates, key-repeat suppression and UTF-16
conversion after emoji. Parser-backed body selection covers Rust, Swift, Go,
Python, JavaScript, TypeScript and Kotlin; Kotlin's multiline default lambda
is not mistaken for the function's body. Abstract/inline declarations remain
unaffected. A headless editable-text assertion originally expected normal text
insertion without a window; the test now checks the relevant behavior directly:
editable keyDown never invokes the fold callback.

Full suite: **273 tests /58 suites**, all pass. Existing fold, source, navigation,
PR and bookmark tests also pass. `make check`/signed build, strict deep codesign,
empty-env `/tmp` resource probe (8 grammars/37 queries/3 scripts) and diff check
pass. Signed executable built **2026-10-11 15:08:18 CDT**. Logs:
`/tmp/radiology-function-x-{check,targeted,tests,build}.log`.

Physical keyboard verification remains unperformed; native key-event tests cover
the dispatch and rendering path. Changes are local on
`codex/toggle-current-function`, after the earlier batch's publication to main.
No live reader restart or viewed-repository mutation.
