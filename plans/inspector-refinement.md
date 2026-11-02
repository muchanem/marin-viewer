# Inspector hierarchy and section cues

**Layout superseded 2026-10-11:** References and Definition/Outline now form
independently scrolling native split panes with a draggable divider. Expanded
references include caller trees. The typography/deduplication/tint work below
remains; outer scrolling and 320-point list budgets are historical. See
[reference-call-trees.md](reference-call-trees.md).

Implemented 2026-10-08 user request: selected symbol visually dominant, smaller
References/Definition headings, avoid repeating the same symbol, improve text
contrast, stack sections at natural heights and use faint background color cues.

Replaced the forced VSplitView/minimum pane heights with
one outer ScrollView and top-aligned sections. Keep native reference/outline
lists with bounded content budgets so long results scroll. Declaration or
explicit-reference identity leads in semantic title3/semibold with kind and
file:line beneath. Small caption/semibold section headings, primary source text
and quiet caption metadata distinguish code from labels. Duplicate definition
name suppression uses exact SCIP identity, retaining different caret targets.
Definition locations show file:line/Here. Dynamic system-blue/teal/purple/neutral
tints at2.5% light/5.5% dark mark sections alongside headings/dividers.

Model/query/navigation identities are retained. Required SwiftUI/macOS/type
skills applied before and after changes. User reader remains untouched.

## Layout and interaction

ContextInspectorView uses an outer ScrollView/top-aligned VStack. The main
symbol/References/Definition sections remain consecutive; there is no draggable
horizontal divider or fixed minimum region reservation. Reference lists budget
30 scaled points per row, file headers and status/disclosure content, capped at
320 points; longer results scroll within their list. Outline similarly has a
bounded content budget. These are compact list budgets, not measured exact
intrinsic list heights. Short/no-content states are compact status rows.
UnderCaretDetailView has no nested greedy ScrollView; expanded signature/docs/
preview take their content height within the outer scroll view.

InspectorSymbolSummary is the prominent heading: semantic SF title3 semibold,
up to two lines, with caption kind and file:line beneath. ContextRegionHeader is
caption semibold; metadata is caption secondary; actual source text is callout
monospace/primary, match/emphasized lines semibold. Definition uses location/Here
when its exact SCIP symbol matches the declaration/explicit-reference heading.
A different caret target retains a body medium name. Equality is by semantic
identity, never spelling. External/local definitions keep their existing facts,
availability and navigation rules.

InspectorSectionBackground uses system blue for the symbol, teal for references,
purple for Definition, and neutral for Outline, over dynamic text background.
Opacity is2.5% light/5.5% dark. Headings and separators independently identify
sections; the backgrounds are decorative and hidden from accessibility.
Source snippets retain copy/text selection and full accessible source, now with
primary text and secondary line numbers. Models/queries/selection/disclosures
and exact-caret navigation remain the existing implementations.

## Validation

Six actual-component renders at220/280/420 points in both appearances include
the heading, real ReferenceRow content, caption headers, definition location and
section backgrounds. Artifacts: build/inspector-review/{light,dark}-*.png.
These test rendering components; the live native review verifies actual lists
and layout. Native PR758/nomex.rs at admit_call: dominant name/kind/file:145,
4 references plus its definition row, compact stacked Definition/location/Here,
no repeated name or large inter-section gap. Screenshot:
build/inspector-review/native-definition.jpeg.

Native reference selection stayed at source145; Right expanded real context;
Return navigated to127; Cmd-[ returned to145 exactly. A separate different-target
live check was not completed: source text selection failed once and source-area
click reported offscreen; the exact-identity branch and model behavior are covered
by source review and existing context tests. No native claim for that case.

First full suite hit the preexisting source-highlight fixed-deadline test with
remaining fade alpha0.06. It passed alone; the full rerun then passed unchanged.
Final gates: **253 tests / 52 suites**, make check/build, strict deep codesign,
empty-env /tmp packaged resources (8 grammars/37 queries/3 scripts), diff check.
Built **2026-10-08 22:59:05 CDT**. Logs /tmp/radiology-inspector-{check,build,
tests,tests-final,highlight-test}.log. No indexing active at shutdown; separate
review app closed, user's reader/repository preserved. Changes local/uncommitted.
