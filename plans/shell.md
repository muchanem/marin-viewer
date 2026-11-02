# Viewer shell (workstream 2)

The shell turns Radiology's reader window into the Marin viewer when a prepared PR is open. It
adds the strip of three cards above the split view, the step sidebar, the viewer toolbar, the
session panel in the inspector and the code windows. The diff reader (`Viewer/Diff/`) draws the
main view; see "How the diff reader is wired" below.

Open a PR with File > Open PR… (⇧⌘O) or launch with `--viewer-pr 10640`. File > Close PR returns
the window to Radiology's reader. Without a PR open, the app is the stock reader.

## Launch arguments

| argument | default | sets |
|---|---|---|
| `--viewer-pr N` | none | opens PR N at launch |
| `--viewer-root DIR` | `~/openathena/marin-viewer` | the root that the other defaults hang from |
| `--viewer-marin DIR` | `<root>/marin` | the read-only Marin clone |
| `--viewer-wordbase DIR` | `<root>/wordbase` | the wordbase checkout; `prs/N/` holds the prepared PR |
| `--viewer-state DIR` | `<root>/state` | the sidecar's state directory |
| `--viewer-prompts DIR` | `<root>/prompts` | the session and pipeline prompts |
| `--viewer-sidecar DIR` | `<root>/sidecar` | the built Agent SDK sidecar (`dist/main.js`) |
| `--viewer-node PATH` | PATH, then Homebrew, then the newest `~/.nvm` node | the node binary |

The shell never runs git in the Marin clone. `ViewerPRLoader` reads changes and head files
through Radiology's `ReviewRepository`, which works in its own cache, and the session's working
directory is the head worktree in that cache.

## AppModel and ViewerStore

Radiology's `AppModel` stays the per-window reader: repository, files, search, semantic index,
inspector panes. The shell adds two objects beside it.

- `ViewerStore` (`Viewer/Store/ViewerStore.swift`, one per app) holds the open PR, the seam state
  below, review notes, diagram layouts, the main session and its forks, toasts and the sidecar
  client. Every window reads it from the environment. It owns no AppKit state.
- `ViewerWindowModel` (one per window) holds what differs between windows: whether the panel is
  presented and on which tab, the zoomed step diagram, the enlarged-diagram sheet, the last box
  or step clicked (the ⌘> target), and the window's own session once promoted. The main window's
  model is `store.mainWindow`.

`RootView`, `RepositorySidebar` and the other Radiology views read both from the environment as
optionals. When either is absent, as in tests and in code windows, they draw the stock reader.
`store.mainReader` points weakly at the main window's `AppModel`; the store uses it to answer the
session's `find_symbol` request from the SCIP index.

## The seam with the diff reader

The store publishes what the main view shows and takes the actions that change it. The diff
reader observes the state and calls the actions; the sidebar, strip, panel and session do the
same, so every route to a location goes through one place.

State, all observable on `ViewerStore`:

| member | meaning |
|---|---|
| `mode: ViewerMode` | `.byStep` or `.byFile` |
| `focusedStepID`, `focusedStep` | the step shown By step |
| `revealRequest: RevealRequest?` | `path`, `line`, `function`, `inStep`, `revision`; a new `revision` means scroll again |
| `blame: Bool` | the toolbar's Blame toggle |
| `hidesTests: Bool` | the Changes tab's Hide tests box |
| `focusedNoteID`, `focusedNote` | the note shown inline and focused in the Review notes tab |
| `wholeFilePaths: Set<String>` | files expanded past their excerpts |
| `stepOrder: [Int]`, `orderedSteps`, `movedSteps` | the step order after a session's reorder, and the steps it moved |
| `notes: ReviewNotes`, `draftNotePaths` | review notes and the files with drafts |

Actions:

| call | effect |
|---|---|
| `focus(step:)` | By step on that step, clears the reveal |
| `step(after:)` | the next step in `stepOrder`, for the Next link |
| `reveal(path:line:function:)` | stays By step when the focused step's excerpts cover the location, else switches By file; a function without a line resolves through `ViewerLocationResolver`, then the code path's fallback lines |
| `open(path:line:)` | By file at that line, as a Changes row, search hit or note link does |
| `focus(note:)` | toggles the inline note and opens the Review notes tab |
| `revealNote(_:)` | focuses the note and opens its line By file |
| `ask(_:from:)` | adds a chip to the window's session and shows the panel; keeps pending memories first |
| `showWholeFile(_:)`, `toggleWholeFile(_:)` | expand a file past its excerpts |
| `openInNewWindow(path:line:)` | opens a code window |
| `openStepDiagram(_:in:)` | zooms a window's PR map into a step diagram, or toasts why it cannot |
| `openCode(of:)` | a step-diagram box's click: `reveal` its code, or toast that it is outside the repository |

### How the diff reader is wired

`openPR` loads the PR's `PRReviewDocument` once, off the main actor, with
`PRReviewLoader().load(prDirectory:wordbaseRoot:repository:)` on the Marin clone (read-only
`git show` and `git blame`). `install(document:)` keeps it as `store.document` and builds the main
window's `DiffReaderModel` as `store.diffReader`. `makeReader(for:)` builds a reader on the same
document for any window, so the document is never loaded twice. Opening another PR or Close PR
drops both.

`ViewerMainView` shows `DiffReaderView` once the reader exists. While the document loads, or if it
fails to, it shows `ViewerMainPlaceholder` (the wordbase's excerpts) under a status line.

While the reader exists it owns the view state, and the store's seam members read through to it,
so the sidebar, strip, toolbar and panel follow what the reader shows:

| store | diff reader |
|---|---|
| `mode` get / set | `model.mode` |
| `focusedStepID` | `model.stepID` |
| `blame` get / set | `model.showBlame` |
| `focusedNoteID` | `model.expandedNoteID` |
| `wholeFilePaths` | `model.wholeFile` |
| `notes` (on every change) | `model.notes` |
| `stepOrder` (on every change) | `model.setStepOrder(_:)`, which `stepPosition` and `nextStep` follow |

Before the reader exists the store keeps the same values itself. `install(document:)` hands them
over, so a step clicked or Blame turned on while the document loads still applies.

The actions call the reader:

| store action | diff reader |
|---|---|
| `focus(step:)` | `focus(step:)` |
| `reveal(path:line:function:)`, so also `openCode(of:)` for a step-diagram box | the line comes from the document's declarations, then the code path's fallback lines, then `ViewerLocationResolver`; then `reveal(path:line:)`, which stays in the step when an excerpt holds the line, or `revealFile(_:)` |
| `open(path:line:)` | `reveal(path:line:)` or `revealFile(_:)` By file |
| `focus(note:)` | `focus(note:)` / `closeNote()` |
| `revealNote(_:)` | By file at the note, then `focus(note:)` |
| `showWholeFile(_:)`, `toggleWholeFile(_:)` | the same calls |

`reveal` and `open` send a path outside the PR's changed files to a code window instead.

The reader's callbacks:

| callback | store |
|---|---|
| `onAsk` | `ask(_:from:)` with the reader's window |
| `onOpenInNewWindow` | `openInNewWindow(path:line:)` |
| `onNoteSelected` | opens that window's Review notes tab with the note focused |
| `onGoToDefinition` | a destination in a changed file scrolls the reader; any other opens a code window there; none shows a toast |
| `definitionLookup` | the main reader's SCIP index (`indexDefinition(of:)`), after the document's own declarations |
| `onSelectionChanged` | a new code selection clears the window's `lastAskTarget` |

Each card's `DiffCodeTextView` publishes its settled selection as `model.selection` (card, path,
head lines, text). ⌘> in the text view asks about it directly. ⌘> from the menu takes the newer of
the last clicked file, step, box or note and the code selection. `selectionContext()` reports the
selection to the session as `selection: {path, lines, text}`.

## Sessions and the sidecar

`SidecarClient` (`Viewer/Sidecar/`) speaks newline-delimited JSON to `sidecar/dist/main.js`. It
correlates requests by id, delivers events to `ViewerStore`, answers `find_symbol` and
`selection_context` within 4.5 s, and restarts the process on the next request after an exit.
`SidecarEnvironment.child` removes `ANTHROPIC_API_KEY`, `CLAUDE_API_KEY` and
`ANTHROPIC_AUTH_TOKEN`, so sessions run on the `claude` login. The client never logs the
environment.

A session opens on its first send, in the head worktree, and resumes the PR's prepared session
when `prs/N/pr.md` records a UUID `session_id`. Promote to Session gives a window its own session,
forked from the main one. Closing a session asks it for memories; the panel lists them, × drops
one, and Done, a new question, closing the window or quitting keeps the rest with `notes.keep`.
Posting sends only approved notes, after the confirmation sheet, through `review.post`.

## Diagrams

`DiagramMetrics` measures each box in the app's fonts (label 10.5 pt, sub 9 pt, code 9.5 pt mono)
and sends the sizes with the diagram to the sidecar's `layout` request. PR-map boxes whose step
has a diagram get 10 pt more for the "+" mark. The sidecar returns positions, the scale that fits
the card (floor 0.8) and `overflow`; `DiagramCard` scrolls an overflowing diagram and offers Open
Larger. Edge labels are measured the same way and sent as `edge_labels`; the sidecar widens the
gap a labelled edge crosses so the label clears both boxes. Measured on #10640, the PR map and
steps 2 and 4 overflow and the rest fit. The PR map overflows because its "loopback" label widens
one gap.

The strip is as tall as the taller of its two diagrams as drawn: an overflowing diagram is 196 pt,
a fitted one is its height scaled to the card's width. It never shrinks below room for the
description's sentence and More.

## Verification

`Tests/RadiologyTests/Viewer/` holds `ViewerLogicTests`, `SidecarClientTests` and
`ViewerStoreTests`, which mock the sidecar with `ScriptedTransport`, and
`ViewerReaderWiringTests`, which drive the diff reader through the store on a synthetic review
document (`ShellFixture.document(for:)`, no git). `ViewerRealDataProbe` is opt-in and runs
against the real wordbase:

```bash
MARIN_VIEWER_PROBE=1 swift test --filter ViewerRealDataProbe/layoutScales
MARIN_VIEWER_PROBE=1 swift test --filter ViewerRealDataProbe/readerByFileAndBlame
MARIN_VIEWER_PROBE=1 MARIN_VIEWER_SNAPSHOTS=<dir> swift test --filter ViewerRealDataProbe/snapshots
MARIN_VIEWER_PROBE=1 MARIN_VIEWER_LIVE=1 swift test --filter ViewerRealDataProbe/liveTurn
```

Point `MARIN_VIEWER_PROBE_WORDBASE` and `MARIN_VIEWER_PROBE_STATE` at scratch copies, since the
live turn can draft a note and `notes.keep` commits to the wordbase.

The built app captures itself. `MARIN_VIEWER_SNAPSHOT=<png>` writes the main window to that file
four seconds after `--viewer-pr` opens. `MARIN_VIEWER_SNAPSHOT_DIR=<dir>` instead walks the window
through five states: step 1, step 6 zoomed, By file on http_service.py with blame, note f1 inline,
and ⌘> on a selection of `_pump`. It writes each state as `live-N-*.png` (`screencapture -l`, which
needs Screen Recording) and `cache-N-*.png` (drawn offscreen), plus `snapshots.log`. Run the binary
directly so the environment reaches it:

```bash
MARIN_VIEWER_SNAPSHOT_DIR=<dir> build/Radiology.app/Contents/MacOS/Radiology --viewer-pr 10640 \
  --viewer-wordbase <scratch wordbase> --viewer-state <scratch state>
```

Offscreen snapshots draw the toolbar's selected segment blank or black; the running app draws it
correctly.

Radiology's sidebar opened at 144 pt, below its 220 pt minimum, in both the stock reader and the
viewer. The cause was modifier order in `RootView`: `.toolbar(removing: .sidebarToggle)` outside
`.navigationSplitViewColumnWidth` hides the width from the split view. `SidebarWidthTests` holds
the fix.
