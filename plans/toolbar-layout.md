# Native toolbar grouping

Requested 2026-10-08 from the user's toolbar critique. Keep SwiftUI's native
toolbar and arrange navigation/repository, PR context, and viewing tools;
move Open Repository into a repository menu and Exit PR into the PR menu;
give the PR selector a visible label and remove the duplicate full PR title.

## Implementation

`ReaderToolbar` supplies native ToolbarItemGroups. Navigation contains the
left-sidebar toggle, Back/Forward, and a semibold repository-name menu.
`RepositoryMenu` contains Open Repository and Open Recent. PR context contains
an explicitly title-and-icon `PullRequestMenu` (#number or Pull Request), with
a visible native menu indicator, and a compact icon-only refresh while active.
Exit PR is a first-level PR-menu action during active/loading review and retains
the existing exit/cancel implementation. Active PRs not in the recent list still
have a selection row. The main Pull Request command menu also names Exit PR.

Viewing tools now use the native selected-value Normal/Critical dropdown and
the per-file Before/After segmented picker together in the principal position.
Search (Go to File, Go to Symbol, Search Repository) and the Context-inspector
toggle remain trailing. Source Files Only/Hide Tests are View-menu options;
toolbar/navigator filter icons are removed. See sidebar-refinement.md for the
latest type/layout acceptance and gates.
Existing model bindings/actions and menu-bar shortcut registrations remain;
SidebarCommands supplies the native left-sidebar command. Inspector recovery
still uses the scene-bound View command and Opt-Cmd-I without requiring source.

The duplicate PR subtitle is removed; its full title remains in the Changes
pane and PR menu/help. The repository remains the window's navigation title,
but the system title toolbar item is removed on macOS15+ so the repository menu
is the single visible label. macOS14 retains its system title behavior. macOS26
adds a native fixed toolbar spacer between navigation and PR context; older
versions use the platform's ordinary toolbar group spacing.

The toolbar is attached to ReaderDetail inside NavigationSplitView's detail
closure. Default sidebar toggles are removed inside both columns, with one
explicit scene-bound navigation toggle retained. Attaching the toolbar outside
the split view initially put primary-action tools above the sidebar and added
a duplicate automatic toggle; native review caught this and the placement was
repaired. Do not move the toolbar back to the split-view parent without review.

Typography: native SF Pro semantic body, regular PR/mode labels, semibold
repository identity. One-line labels with bounded repository-name width and
middle truncation; no new type scale, source font, backgrounds, or custom
window chrome. Applied swiftui-pro before/after code decisions, macos-design,
typography-designer, and build-macos-apps swiftui-patterns.

## Native review and gates

The evidence below is historical for the first grouping pass. Latest dropdown,
revision, menu-only filters and sidebar tabs are verified in sidebar-refinement.md.

Computer Use inspected a separately signed `RadiologyToolbarReview.app`, bundle
id `org.sockpuppet.radiology.toolbar-review`, on actual tkos PR758. The user's
reader was not operated or restarted. Verified visible tkos and #758 labels,
compact refresh, Normal/Critical and trailing filter/search/Context controls,
no duplicate PR title, no duplicate sidebar toggle, and no overflow at the
ordinary window size. The PR's full title remains in Changes and menu/help.

Repository menu shows Open Repository/Open Recent; PR menu shows Exit PR as
its first action, the active PR row even outside the recent25, and related PR
commands. Search contains Go to File/Go to Symbol/Search Repository. The Source
Files Only toolbar toggle changed the Changes list and navigator toggle together;
the filter icon's state and accessibility value changed to Active. Sidebar
button collapsed navigation, Ctrl-Cmd-S restored it, with caret8 unchanged.
Exit PR was physically activated from its menu and returned this review instance
to Files/local checkout: selector reads Pull Request and refresh is removed.

The final review also verified the user's subsequent gutter changes, live
Go to Line7 and Down to8. Screenshots:
- [Ordinary toolbar/filter state](/Users/tqbf/codebase/radiology/build/toolbar-review/normal-width.jpeg)
- [Final toolbar and compact gutter at caret7](/Users/tqbf/codebase/radiology/build/toolbar-review/compact-gutter-caret7.jpeg)
- [Arrow movement to caret8](/Users/tqbf/codebase/radiology/build/toolbar-review/compact-gutter-caret8.jpeg)

Narrow-window resize remains unverified: both drag attempts (bundle id, then
full app path) failed `-10005: noWindowsAvailable`. Full-path state recovery
worked, but further drag attempts were stopped. Ordinary layout and menu/button/
keyboard operations succeeded. Review-only indexing was canceled before closing
the review process; source/code and the user's existing reader were preserved.

Combined final gates: **246 tests / 51 suites**, compile/build, strict deep
codesign, empty-environment packaged resources, diff check. Signed
**2026-10-08 16:10:23 CDT**. No new tests just for these low-impact menu/layout
edits; the two new tests cover native sparse-gutter drawing/caret/folds/scroll.
