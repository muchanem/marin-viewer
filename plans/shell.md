# Viewer shell (workstream 2)

The shell turns Radiology's reader window into the Marin viewer when a prepared PR is open. It
adds the strip of three cards above the split view, the step sidebar, the viewer toolbar, the
session panel in the inspector and the code windows. The diff reader (workstream 3, branch
`mark/diff-reader`) draws the main view. Until that branch merges, `ViewerMainPlaceholder` lists
what the diff reader will show for the focused step.

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

### Mapping to `DiffReaderModel` at merge

`ViewerMainPlaceholder` is the one view to replace. The replacement builds a `DiffReaderModel`
from `PRReviewLoader().load(prDirectory: wordbase/prs/N, wordbaseRoot: wordbase, repository: head
worktree)` when `store.pr` changes, then keeps the two in step.

| store | diff reader |
|---|---|
| `mode` | `model.mode` (both directions) |
| `focusedStepID` | `model.focus(step:)` |
| `revealRequest` with `inStep` | `model.reveal(path:line:)` |
| `revealRequest` without `inStep` | `model.revealFile(_:)`, then `reveal(path:line:)` when a line is known |
| `blame` | `model.showBlame` |
| `focusedNoteID` | `model.focus(note:)` / `closeNote()` |
| `wholeFilePaths` | `model.showWholeFile(_:)` |
| `notes` | `model.notes` |
| `ask(_:from:)` | `model.onAsk` |
| `openInNewWindow(path:line:)` | `model.onOpenInNewWindow` |
| `focus(note:)` | `model.onNoteSelected` |
| `reveal(path:line:)` | `model.onGoToDefinition`, after `definitionLookup` |

Two gaps remain. `DiffReaderModel` takes its step order from the document, so a session's reorder
(`stepOrder`, `movedSteps`) needs a setter there. `selectionContext()` reports mode, step, note,
location and chips, and the diff reader's text selection should join it once the reader exposes
one.

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
Larger. Measured on #10640, steps 2 and 4 overflow and the rest fit.

## Verification

`Tests/RadiologyTests/Viewer/` holds `ViewerLogicTests`, `SidecarClientTests` and
`ViewerStoreTests`, which mock the sidecar with `ScriptedTransport`. `ViewerRealDataProbe` is
opt-in and runs against the real wordbase:

```bash
MARIN_VIEWER_PROBE=1 swift test --filter ViewerRealDataProbe/layoutScales
MARIN_VIEWER_PROBE=1 MARIN_VIEWER_SNAPSHOTS=<dir> swift test --filter ViewerRealDataProbe/snapshots
MARIN_VIEWER_PROBE=1 MARIN_VIEWER_LIVE=1 swift test --filter ViewerRealDataProbe/liveTurn
```

Point `MARIN_VIEWER_PROBE_WORDBASE` and `MARIN_VIEWER_PROBE_STATE` at scratch copies, since the
live turn can draft a note and `notes.keep` commits to the wordbase. `MARIN_VIEWER_SNAPSHOT=<png>`
makes the built app write its main window to that file four seconds after `--viewer-pr` opens.

Offscreen snapshots draw the toolbar's selected segment blank or black; the running app draws it
correctly. Radiology's sidebar comes up at 144 pt in both the stock reader and the viewer, below
its declared 220 pt minimum, so step titles truncate until the sidebar is widened.
