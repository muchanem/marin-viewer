# Changes sidebar and toolbar refinement

Implemented 2026-10-08, incorporating toolbar, Changes-row and sidebar-tab requests.

Requested toolbar: Normal/Critical becomes a selected-value dropdown, initially
Normal; Before/After moves beside it; Source Files Only/Hide Tests are menu-only.
Implemented SourceModePicker/SourceRevisionPicker in ReaderToolbar's principal
group, removed toolbar/navigator filter icons, and kept View menu toggles and
shortcuts with Show All Files. Breadcrumb retains change/collapse buttons.
First gates passed: 253 tests/52 suites, compile/build. Separate native PR758
verified Normal default, Critical selection, Cmd-1 reset, Before/After switching,
and View Source Files Only changing 26→30 files without changing caret1/After.
Initial screenshot: build/toolbar-controls-review/normal-after.jpeg.

## Sidebar implementation

`SidebarModeTabs` replaces the labeled segmented picker. Equal-width native
buttons use body SF regular/secondary when inactive and semibold/primary when
selected, with a two-point accent underline and selected accessibility traits.
Changes appears only during review. Mouse activation gives the tab keyboard
focus; Left/Right move between available modes and focus the next tab. Search
then focuses its existing field. There is no Browse caption. Source mode and
sidebar mode continue to use their existing separate model properties.

`ReviewChangeRow` and `ReviewChangeStatus` preserve two-line rows and native List
selection. Filenames use body/medium, semibold when selected; directories and
counts use caption/secondary. Names and paths truncate in the middle with full
path/status help. Counts have tabular numerals, a shared 64-point minimum lane,
right alignment and room to expand for larger values. Counts/status align with
the filename line. Modified uses an explicit monospaced caption semibold M;
additions retain circled plus, with existing other status symbols. Binary counts
say binary while preserving file status. The selected row gains an 8% accent
background and two-point accent marker; native selection remains authoritative.

The PR summary gains 12-point top/bottom insets and an 8-point separation before
the list. It shows title, PR number/state, and visible additions/deletions;
duplicate file-count text moves to the footer. The footer displays counts and
named active filters, such as `18 of 30 files · Source only · Tests hidden`.
Hidden-open-file notices remain. Full PR head SHA moves to the Git icon's help/
accessibility so it cannot consume the visible filter labels.

## Validation

Actual production tabs/rows rendered at 220/280/400 points in both appearances:
modified/added/deleted/renamed/binary, long names, varied counts and selected
marker. The initial off-window List probe deferred its cells; the final renderer
uses actual row views in a stack. Artifacts: build/sidebar-review/{light,dark}-*.png.

Native separate-instance tkos PR758 review verified tab-like appearance without
Browse, primary names/quiet paths/trailing counts, M/plus statuses, Core.kt
selection and accent marker, and mouse Changes/Files/Search selection. Initial
keyboard check found arrow input still reached the source viewer; explicit
button focus fixed it. Final Files click focuses that tab, Right selects Search
and focuses its field, Changes restores the review list. Source mode's duplicate
accessibility caption was removed; final Normal is announced once.

Live View menu checks: Source Files Only changed Files to `5509 of 7019 files ·
Source only`, Changes to `26 of 30 files · Source only`; Hide Tests then produced
`18 of 30 files · Source only · Tests hidden`. Initial toolbar review verified
Critical/Normal shortcut synchronization and Before/After beside the dropdown.
Show All Files stays enabled only while a filter is active. Screenshots:
build/sidebar-review/native-combined.jpeg, native-selected-core.jpeg,
native-source-only.jpeg, native-both-filters.jpeg, native-final-tabs.jpeg.

Required swiftui-pro, macos-design and typography-designer guidance applied.
Final gates: **253 tests / 52 suites**, make check/build, strict deep codesign,
empty-environment /tmp packaged resources (8 grammars/37 queries/3 scripts),
diff check. Built **2026-10-08 17:35:01 CDT**. Logs
/tmp/radiology-sidebar-{check,tests,build}.log; initial toolbar logs use
/tmp/radiology-toolbar-controls-*.log. Required skills reapplied after code.
No new tests for these reversible UI changes. Final review app closed with no
indexing active; user's reader and repository contents preserved. Changes local/
uncommitted. Older segmented-mode, filter-icon and source-header revision-layout
descriptions are superseded by this contract.
