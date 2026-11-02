# Source breadcrumb layout

Requested 2026-10-08: keep the existing toolbar/source-header arrangement, give
revision controls their own fixed trailing area, and protect the file/final
declaration from long directory prefixes. The user's follow-up asks to retain a
couple more entries whenever space allows.

## Implementation

`SourceBreadcrumbs` remains the single 32-point source header. It gives the
remaining leading width to `SourceBreadcrumbPath`. The user's later toolbar
request moved Before/After into `SourceRevisionPicker`, a 136-point segmented
picker beside the Normal/Critical dropdown. The header retains only 50-point
changed-block controls and the existing 28-point Collapse Functions button,
freeing another144 points for path context. Status/rename details remain in the
toolbar picker's help/accessibility. See [the latest UI pass](sidebar-refinement.md).

`SourceBreadcrumbPath` uses native `ViewThatFits` measurements with the actual
semantic UI font. `SourceBreadcrumbVariant` supplies a flat, uniquely identified
list of alternatives. It first tries the complete declaration chain while
progressively dropping directories from the beginning. Each remaining path
suffix is tried with and without the repository label, allowing nearby folders
to use space previously occupied by the repeated repository identity. Only
after that complete declaration chain cannot fit does it drop outer declarations,
again filling available space with nearby directories. This replaces the
initial coarse full-path / no-directories / one-declaration steps.

File plus final declaration are retained whenever they fit. Extreme widths
prefer the final declaration, or the filename outside any declaration, before
middle truncation becomes necessary. The path stays within its allotted width;
there is no horizontal breadcrumb scrolling or new toolbar row.

The ellipsis is a native, 20-point menu. It shows the complete repository-relative
path and every enclosing declaration through the existing selection callback.
The full location is also available as help. SourceBreadcrumbTrail/Separator
share the rendering of every alternative. The existing model supplies the
enclosing-declaration chain; this change concerns its presentation.

Typography follows the existing scale: semantic SF callout (`Theme.Fonts.meta`),
regular secondary directories/repository/outer declarations, primary regular
filename, primary medium final declaration. Chevrons use caption2/tertiary and
are hidden from accessibility. No smaller font is used to squeeze in more text.
Required swiftui-pro, macos-design and typography-designer guidance applied.

## Validation

The measurements and screenshots below describe the preceding header revision
layout. The current, wider breadcrumb is verified in sidebar-refinement.md.

Actual production view files were compiled into the disposable
`build/breadcrumb-review/render` probe and rendered through NSHostingView at
1100, 740, 560, 440 and 360 points in both appearances. The granular revision
shows `src` plus all three fixture declarations at 740; filename and two
declarations at 560; filename/final declaration at 440; complete final name
at 360. Revision/change/collapse controls remain in their trailing area.
Artifacts: `build/breadcrumb-review/{light,dark}-<width>.png`.

The first granular attempt used nested ForEach alternatives and the render probe
caught a ViewThatFits child-ID collision. The flat Identifiable variant list
fixes it; all ten renders now complete. Keep alternative IDs unique across the
entire ViewThatFits list, not just within a nested loop.

The preceding native header build was inspected in a separately identified
RadiologyToolbarReview.app on tkos PR758/nomex.rs. Before/After switched correctly;
Go to Line150 showed the file and Nomex/admit_call; the ellipsis menu exposed the
full path and both declarations. Screenshot: `build/breadcrumb-review/native-pr758.jpeg`.
The menu initially held automation's keyboard events; its exposed Cancel action
restored the main window. The test app was closed; the user's reader stayed open.

The final granular build was inspected live at the same ordinary window size.
With the caret at line150, the header retains
`… › crates › harness-core › src › nomex.rs › Nomex › admit_call`, adding three
nearby directories to the initial compact header while keeping both declarations
and fixed revision controls. Initial file opening also exercises the empty
declaration chain; Go to Line exercises its transition to two declarations.
Screenshot: `build/breadcrumb-review/native-more-context-pr758.jpeg`.
No indexing was active at closure; the separate review app was quit and the
user's reader remains running. Physical window resizing was not attempted;
five-width production-view renders provide the narrow-width evidence.

Final gates: **253 tests / 52 suites**, `make check`, `make build`, strict deep
codesign, empty-environment packaged resource verification from `/tmp`
(8 grammars, 37 queries, 3 indexing scripts), and diff check. Built executable
stamped **2026-10-08 17:02:10 CDT**. Logs:
`/tmp/radiology-breadcrumb-{check,tests,build}.log`. Skills reapplied to the final
view/data/type review; changes remain local/uncommitted.
