# Context inspector pane controls

Implemented 2026-10-11 after the user requested an interface for enabling and
disabling panes in the right sidebar.

Code Paths moved to the left navigation sidebar on 2026-10-31; its retired
`contextPane.codePaths` preference is ignored. Bookmarks remains independent.
See [Code Paths](code-paths.md).

## Interface and behavior

The inspector has a small persistent **Context** header with a labeled **Panes**
menu. The same checked choices appear under **View > Context Panes**:

- References (including its enclosing-symbol summary).
- Definition / Outline.
- Trait Implementations (contextual Rust trait results).
- Bookmarks.

All choices default on. **Show All Panes** restores those defaults. Each choice
persists app-wide across repository changes and relaunches. Hiding a pane only
changes presentation; source bytes/caret/viewport, history, bookmarks, semantic
indexes, row selections and disclosure state are retained.

Definition/Outline and Implementations still share the middle slot. A trait
context shows Implementations when enabled; otherwise Definition/Outline is
used when enabled. With both disabled the middle slot is omitted. If only
Implementations is enabled outside a trait context, no content pane is active;
the empty state explains when it appears.

Remaining panes reclaim the available height. Three panes use the existing
nested native VSplitViews; two use one native split, and one fills the inspector.
No disabled pane leaves a blank split child or unused height. Each displayed
pane retains independent scrolling and the appropriate minimum height.

The Panes menu remains when everything is disabled. **No panes enabled** offers
a direct **Show All Panes** button; context-only emptiness offers the same
recovery. The toolbar/View/⌥⌘I whole-inspector controls remain separate. Enabling
a pane from View while the inspector is closed reopens it via RootView's existing
presentation state. No source file is required to configure or restore panes.

When References is hidden, Definition displays its symbol name rather than
deduplicating against an invisible upper heading. Trait Implementations now
uses a compact caption and flat click-to-navigate rows without a separate trait
heading or expansions; see [rust-trait-implementations.md](rust-trait-implementations.md).

## Implementation

`InspectorPanes` is an Equatable value held by `AppModel`, following the existing
SourceFilters persistence pattern. Nested direct Bindable writes trigger the
model's guarded didSet and save four UserDefaults booleans:
`contextPane.references`, `contextPane.definition`,
`contextPane.implementations`, and `contextPane.bookmarks`. Missing keys mean
enabled, preserving the previous default layout for existing installations.

`InspectorPaneMenuContent` shares native Toggles and the Show All action between
the in-inspector menu and ReaderCommands. No duplicate preference state or manual
get/set bindings are introduced. `RootView` observes an increased enabled count
to reopen its existing inspector binding; it does not force presentation on
ordinary context/caret changes.

`InspectorPanes.visiblePanes(hasTrait:)` selects at most three physical regions.
`InspectorPaneStack` composes exactly those regions. `InspectorPaneView` supplies
stable frame roles and flexible containers, retaining native divider behavior.
The underlying ContextModel and BookmarkModel are not reset when panes disappear.

SwiftUI guidance was applied before and after implementation, particularly
observable data flow, direct bindings, separate view types, accessibility and
cheap layout decisions. macOS design guidance informed a labeled native checked
menu and a recovery route in View. Typography uses the established system scale:
caption semibold secondary header, caption regular native menu label, headline
primary empty-state title, callout secondary explanatory text and a native small
button. No new font scale, custom window chrome or animated geometry was added.

## Verification and limits

Fresh sequential gate: **291 tests /63 suites pass** with
`swift test --no-parallel`; check/build, strict deep signing and packaged
resources pass, signed at **2026-10-11 16:39:26 CDT**. Two parallel full runs hit
the Files manual-scroll timing assertion; that test passes alone, with the pane
suite, and in the full sequential run. Files code/assertions were not modified.
Parallel GUI timing remains a test-suite limitation, recorded in PROGRESS.md.

`InspectorPaneTests` verifies defaults/persistence including all-off/restore,
all 16 preference combinations through the actual NSHostingView/NSSplitView
layout, omitted split children, restored divider resizing, and retained
reference selection/disclosure, definition disclosure, bookmarks, source bytes,
navigation target and history. A real Rust fixture proves native implementation
list removal/definition fallback and preservation of implementation selection
and preview state. Existing inspector/trait divider tests remain acceptance
checks for the default layout.

Twelve production inspector renders cover all-enabled/all-disabled at
220/280/420-point widths in light/dark. They use unshown NSWindows so native list
cells render, without opening or restarting the user's reader. Artifacts:
`/tmp/radiology-pane-renders/`. The new controls are visually inspected; physical
menu clicking and closed-inspector recovery remain unperformed in the shared
reader. The newest PROGRESS.md carries final test/build/signing/resource gates.

Changes are local on `codex/toggle-current-function`, retaining earlier x-key,
Files-follow-navigation and trait-implementation work. No viewed-repository
writes, push, merge or shared-reader restart were performed.
