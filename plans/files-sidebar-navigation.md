# Files sidebar follows source navigation

Implemented 2026-10-11. In Files mode, source navigation expands the current
file's parents, selects its native row, and scrolls toward its center. This also
runs when returning from Search/Changes to Files and for explicit same-file
jumps. Native bounds clamp centering near list edges. Passive caret movements
and manual list/folder browsing do not repeatedly recenter the list.

## Implementation

RepositoryFilesView wraps its List in ScrollViewReader; leaf paths are explicit
scroll IDs in both tree and flat filter modes. FileTreeExpansion.reveal unions
only parent paths into the existing expanded set. A task keyed by snapshot root,
selected path, loaded path, navigation revision, query and source filters expands
parents, sets view-local selection, yields for child rows to materialize, then
scrolls with a center anchor. Mounting Files starts the same task. Cancellation,
mode/root/path guards reject superseded work.

Selection synchronization never reopens the current file: openSelection requires
a different, listed path in the current repository. Exact bookmark/search caret,
Before/After revision and history therefore survive the highlight/scroll. Root
checks also reject selection callbacks from a previous repository's view.

FilesSidebarPresentation derives a temporary current-file exception over the
filtered tree/list, preserving filters, query, original model data, search, quick
picker and Changes behavior. Only the active document is added. Before-only PR
paths and successfully loaded files outside the snapshot listing can be shown;
unconfirmed missing paths are not invented. FileNode.revealing copies/inserts
only that ancestor chain with directory-first natural ordering. The exception
disappears as the active document changes.

The current Before row gets an existing caption regular/secondary label. Its
Reveal in Finder action uses the materialized Before root. Footer counts include
extra tree documents and report “current file revealed” for filter exceptions.
Other file typography and native selection/disclosures remain. Applied swiftui-pro
before/after, macos-design, and typography-designer for the revision label.

## Evidence

Four new tests include two real native list integrations through NSHostingView,
a detached test window, NSTableView and NSScrollView. In181 files, bookmark
navigation to a/deep/file055 expands/selects and exactly centers its row midpoint
in the viewport. Manual sidebar scrolling survives a caret move; an explicit
same-file jump recenters. Search navigation to b/deep/file044 then returning to
Files preserves byte19/navigation/history while selecting/centering the row.
A disposable real Git PR validates deleted src/old.rs Before at byte5 with both
source filters and a nonmatching query, then switching to the tree. Pure tests
cover exceptions, missing destinations and unrelated folder expansion.

Full suite **277 tests /59 suites**, make check/signed build, strict deep codesign,
empty-env /tmp resources (8 grammars/37 queries/3 scripts) and diff check pass.
Signed executable built **2026-10-11 15:37:26 CDT**. Logs:
`/tmp/radiology-files-reveal-{check,targeted,tests,build}.log`.

Physical live-reader interaction was not performed; actual native selection and
scroll geometry are verified by tests. Changes are local with the x-key work on
codex/toggle-current-function; no user-reader restart, tkos writes, push or merge.
