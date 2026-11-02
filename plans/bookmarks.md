# Repository and PR bookmarks

Implemented 2026-10-11. The right Context inspector now has a third, independently
scrolling **Bookmarks** pane beneath References and Definition/Outline. Both
horizontal dividers are movable. This extends the caller-tree/pill work without
changing its behavior.

## User interaction

- **⌘D**, Bookmarks > Bookmark Location/Remove Bookmark, or the pane's bookmark
  button toggles the exact source caret location. Passive scrolling never changes
  the location being bookmarked.
- The first ten entries use **⌘0 through ⌘9**, in that order. Empty slots are
  disabled. Additional bookmarks remain clickable without a number shortcut.
- Clicking a bookmark or pressing Return on its selected row navigates. Its
  departure is the genuine source caret; Back returns there exactly.
- The native List's drag reorder updates and persists the order. Context menus
  provide Move Up, Move Down, Move to Shortcut and Remove Bookmark; native list
  deletion is also wired. Reordering preserves UUIDs and selection, and immediately
  reassigns the numbered slots.
- Existing source-mode shortcuts move to **⌥⌘1 Normal / ⌥⌘2 Critical** so plain
  Command-number shortcuts belong to bookmarks. Folding shortcuts retain their
  existing distinct modifiers.

The header names the active PR or Checkout. Rows show a body-medium declaration
name (filename fallback), caption path/line, an explicit Before/After label for
review locations, and a quiet tabular shortcut hint for the first ten. Full
path/column and keyboard/reorder guidance remain in help/accessibility. A faint
system-orange section background uses the existing 2.5% light/5.5% dark scheme.
Empty states explain ⌘D and scope; failed jumps explain the issue locally.

## Persistence and identities

`BookmarkScope` consists of the canonical attached checkout path and optional PR
number. Checkout, PR1, PR2, and another repository each have separate lists.
Separate clones are separate attached repositories. The namespace never uses an
evictable app-owned worktree or a head SHA, so PR refresh/reopen keeps its list.
`AppModel.beginOpening` clears the active scope during a repository transition
and activates the confirmed attached-root/PR scope after listing succeeds.
Failed/superseded opening cannot repopulate another scope. PR refresh retains the
same scope and order while replacing the reader snapshot.

`BookmarkStore` persists ordered Codable `SourceBookmark` arrays in injected
UserDefaults under `repositoryBookmarksV1`, keyed by a NUL-separated path/scope
string. Saves reread the archive to preserve all other scope lists. Loading
filters invalid relative paths/coordinates and duplicate UUIDs; malformed data
loads as empty. Tests use disposable preference domains. No repository files,
Git state, or external accounts are written.

Each bookmark stores a stable UUID, relative file path, explicit optional review
revision, canonical UTF-8 byte, line/byte column, label, source blob digest, and
bounded line/neighbor anchors. Same-document exact locations toggle one entry.
Before and After at an identical path/byte remain separate.

## Navigation and changed source

`BookmarkResolver` runs reading, digest verification and relocation off MainActor.
It uses the open buffer when that exact document is already on screen, otherwise
reads through SourceStore and the existing Before-materialization route. Unchanged
bytes use the stored exact offset. Changed files relocate a uniquely matching
saved line, using neighboring lines when needed; ambiguous, edited, blank-only
or unavailable anchors produce an error without changing source/history. Missing
files remain saved and removable rather than disappearing from the list.
Renamed paths are not inferred.

Successful relocation updates the stored position/digest/anchors while keeping
the UUID, label, order and shortcut. Toggling at the relocated caret removes the
same bookmark. Long lines retain exact-byte support but may lack an anchor after
changes. Unicode offsets clamp at scalar boundaries; CRLF lines are supported.

Bookmark jumps preserve their saved Before/After revision. The existing semantic
navigation entry point still chooses After, then delegates to the shared
`navigateFromCaret(from:to:)` history/highlight path; bookmarks use that shared
path directly after resolving their own revision. Requested jumps check scope,
snapshot root, navigation revision, caret revision, cancellation and whether the
bookmark still exists before committing. Repository transitions cancel work.

## Split layout and implementation

`ContextInspectorView` uses two nested native VSplitViews: References versus the
lower group, then Definition/Outline versus Bookmarks. The first prototype's flat
three-child split would not resize its second divider in the actual hosted
NSSplitView test. Nested two-child splits pass both divider checks and preserve
native macOS behavior. Minimum pane heights are 150/100/100 points; the lower
group reserves its combined minimum plus a divider. Each List or Definition
ScrollView fills its pane.

The macOS14 deployment target does not support EnumeratedSequence's newer
RandomAccessCollection conformance. `BookmarkListEntry` supplies stable UUIDs and
current slot indices to ForEach without relying on that macOS26-only API.
State stays in a MainActor observable BookmarkModel; views use native bindings,
buttons, menus, semantic fonts and list reorder callbacks. Applied swiftui-pro
before decisions and after implementation, plus macos-design and
typography-designer.

## Evidence and remaining UI checks

Fresh full suite: **269 tests /57 suites**, all pass. Six new tests cover scope
isolation, persisted ordering/deletion, twelve entries/slot promotion, exact
Unicode/CRLF coordinates and relocation/ambiguity, malformed preferences/invalid
moves, exact-caret Back after slot jumps, relaunch, source-insertion relocation
and toggle, real disposable Git PR Before/After jumps, separate PR numbers using
the same head, checkout/another repository, missing files and superseded jumps.
Existing context, semantics, PR refresh, source and caller-tree tests also pass.

The production inspector hosted in AppKit exposes the two nested NSSplitViews.
Tests move both dividers, assert affected pane sizes, and preserve reference
selection/disclosure and definition disclosure. Initial flat-split failures led
to the nested layout. A preexisting fake-client helper traps when initialized
with duplicate base/head pairs; the new PR fixture initializes one pair and adds
the second PR summary afterward.

Six actual BookmarkRow/header renders at220/280/420 in light/dark cover long names,
relative paths, both review revisions, all ten assigned slots and two unassigned
entries. Artifacts: `build/bookmarks-review/{light,dark}-*.png`. Reproduce with:

```sh
RADIOLOGY_BOOKMARK_RENDER_DIR="$PWD/build/bookmarks-review" swift test --filter ContextInspectorLayoutTests
```

`make check`, signed `make build`, strict deep codesign, empty-env `/tmp` packaged
resource probe (8 grammars/37 queries/3 scripts), and diff check pass. Signed
executable built **2026-10-11 14:41:15 CDT**. Logs:
`/tmp/radiology-bookmarks-{check,integration,tests,build}.log`.

Desktop automation remains unavailable in this session (the earlier @oai/sky
runtime is absent; there are no direct desktop-control tools). Physical list
drag, context-menu/Command-number activation and mouse divider dragging remain
unverified. No live app interaction, reader restart, tkos writes or merge.

Manual acceptance: add twelve bookmarks with ⌘D; verify first/last assigned slots
are ⌘0/⌘9; drag the twelfth to first and check the new ⌘0 target; move it with the
context menu too. Resize both dividers and scroll each pane. Jump between saved
Before and After entries and Back. Switch PR/checkout/repository, then relaunch;
each scope must restore its own order. Verify ⌥⌘1/⌥⌘2 still change source mode.
