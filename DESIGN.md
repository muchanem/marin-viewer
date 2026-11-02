# Marin viewer: design

Status: design for the build, 2026-11-01.

The Marin viewer is a native Mac app for reading the Marin repository and reviewing its pull requests,
with a Claude Code session in a right-hand panel. It is a fork of tqbf/radiology merged with the HTML
demo in `demo/`. A terminal poller keeps code descriptions current as commits reach Marin's `main` and
prepares each PR that requests Mark's review before he opens it.

- Demo (UI reference): https://claude.ai/artifact/AKP994b6esfdur3zoWZ8Cu, source in `demo/`.
- Radiology: https://github.com/tqbf/radiology at `7edfc79`.

## 1. How details get decided

1. Mark's decisions, listed in section 2.
2. The demo: everything it shows is kept, and its behavior wins over Radiology's where the two differ.
3. Everything else follows Radiology, or Zed where Radiology has no equivalent. That covers shortcuts,
   menus, history, search, filters, folding, PR checkout and the many small behaviors nobody wrote down.
   The references are Radiology's `README.md` and `Sources/Radiology/Help/KeyboardShortcuts.md`, then
   Zed's `assets/keymaps/default-macos.json` and docs.

A new shortcut takes Zed's binding for the same action when that binding is free in Radiology. Ask is
⌘> (Zed's `agent::AddSelectionToThread`), because Radiology already uses ⌘L for Go to Line. Every
added shortcut goes into `KeyboardShortcuts.md`.

## 2. Decisions

From Mark:

- Native Mac app. No Electron. Light mode only.
- No Zed fork: Zed's main takes about 105 commits a week, and Zed carries much the viewer does not use.
- Claude runs through the Claude Agent SDK on the Max plan.
- The app reads a fresh clone of Marin at the latest `main`, kept at `~/openathena/marin-viewer/marin`.
- A background poller, started by hand in a terminal, updates descriptions as commits reach `main` and
  prepares PRs that request Mark's review.
- A PR opens by step. The top strip stays visible.
- The left sidebar has Code path, Changes, Files and Search tabs.
- Asking has no buttons. It starts from the right-click menu or ⌘> on a code selection, a file in any
  sidebar tab, a file header, a step, a diagram box or a review note.
- Double-clicking a box in the PR map opens that step's diagram, if the step has one.
- Descriptions come in three layers: a sentence, a paragraph, several paragraphs. The later two are
  collapsed. The demo's hand-written descriptions meet the standard.
- Memories record what a session learned. Bugs go to GitHub review notes or Echo, not to memories.
  Proposed memories each get a discard ×. The rest are kept when Mark presses Done, starts a new
  session, or closes the window or the app.

From the demo (keep all of it):

- **Toolbar:** PR crumb with title, state pill and counts; By step / By file switch; Blame toggle.
- **Top strip:** three cards.
  - The PR description with "More" and "Full description".
  - "In Marin": the subsystem map, with the current subsystem highlighted and the backends this PR
    touches marked.
  - "Inside this PR": the PR map, with a + on boxes that have a step diagram. Double-click zooms in,
    the breadcrumb or Escape zooms out, and clicking a box in a step diagram scrolls to its code.
- **Code path tab:** numbered steps, each with a title and a one-sentence summary. Selecting a step
  shows a step header (kicker, title, layered summary) and that step's excerpts in order, plus a "Next"
  link. A step the session moved carries a "moved by session" tag.
- **Changes tab:** Radiology's two-line rows (name, then a quieter path), status letter, right-aligned
  counts, a dot on files with draft notes, a Hide tests filter and a footer such as
  "21 of 30 files · tests hidden".
- **Files tab:** the focused tree.
  - Changed files are listed with step-number badges.
  - Unchanged files hide behind "+ N unchanged", and unchanged folders behind one count.
  - Tests start collapsed. Changes outside the subsystem appear under "Elsewhere".
- **Search tab:** ripgrep over the checkout, with results grouped by file.
- **Main view:**
  - Diffs first: changed lines plus 3 lines of context. Gaps read "N unchanged lines" with "Show 15
    above", "Show 15 below" and "Show all".
  - A Whole file / Diff only toggle per file, and file cards that collapse.
  - Sticky file headers carry the file's one-sentence description with "More".
  - Deleted lines appear inline, in red.
  - In By file mode, cards scroll file by file, source first, then tests, then other paths.
- **Blame gutter:** short SHA, author's first name and age, shown on the first line of each run, with
  the commit summary as a tooltip.
- **Review notes:**
  - A gutter dot marks each note: amber for drafts, blue for Mark's own, grey once resolved.
  - Clicking the dot shows the note inline below the line and focuses it in the panel.
  - Note cards show status and severity pills, a location link, the author, the layered text, and
    Approve / Reject / Back to draft.
  - "Post N approved notes" opens a confirm box with the exact text to be posted.
- **Right panel:** title "PR #N session" with a cwd and commit subtitle, and × to close. Tabs are
  Session and Review notes.
  - The Session tab shows a collapsed record of the preparation turn, the messages, and any
    session-proposed view changes with Apply / Undo.
  - Chips above the input carry the selection kind and location. Enter sends.
  - Closing the panel shows the proposed memories. A slim "Open PR session" strip reopens it.
- **Context menus:**
  - On code: go to definition, open the definition in a new window, ask about the selection, the
    symbol or the line, and toggle blame.
  - On files: ask, open in a new window, show the whole file.
  - On diagram boxes: ask, go to the step, open the step diagram, open the box's code.
- **Navigation:** ⌘-click goes to definition, and Radiology's Return-on-caret works too.

Choices made in this design that Mark may revisit:

- Radiology's Context inspector (References, Definition, Implementations, Bookmarks) becomes a third
  tab of the right panel, "Context", beside Session and Review notes. Radiology's ⌥⌘I toggles the
  whole right panel.
- Outside PR review, the strip shows the open subsystem's page: its description, its place in Marin
  and its own map.

## 3. Prerequisites

These need Mark before or during the build:

- **Xcode 26.** Radiology's `Package.swift` requires `swift-tools-version:6.2`. A build on the
  Command Line Tools (Swift 6.1.2) with that version lowered fails at only three sites:
  - `isolated deinit` in `ReaderTextView.swift:119`, which needs Swift 6.2;
  - `ToolbarSpacer` in `ReaderToolbar.swift:21`, which needs the macOS 26 SDK;
  - `@Entry` in `ContextInspectorFocus.swift:6`, which needs SwiftUI's macro plugin, shipped only with
    Xcode.

  Until Xcode 26 is installed, Swift work goes into `Packages/ViewerCore`, a SwiftUI-free local package
  (tools-version 6.0) that builds on either toolchain and that the app target depends on.
- **The API key for background runs** (Console organization linked to the Max plan) is `CLAUDE_API_KEY`
  in `~/openathena/marin-viewer/.env`, which is gitignored. The sidecar reads it from there and passes
  it as `ANTHROPIC_API_KEY` to background runs only. Interactive sessions use the existing `claude`
  login.
- **GitHub remote:** `origin` is `git@github.com:muchanem/marin-viewer.git`; `upstream` is
  `https://github.com/tqbf/radiology`. Pushes happen only when Mark asks.
- **Optional:** ask tqbf to add a LICENSE file. The author has said the project is open for others to
  use, but the repository has none at `7edfc79`.

These the build agents can install themselves: `scip-python` (`npm i -g @sourcegraph/scip-python`,
which needs Python 3.10+), the sidecar's npm dependencies, and a `claude` login check. Present already:
`gh` (logged in as muchanem), `rg`, `git`, `node` 22, `uv`.

## 4. Layout on disk

The repository at `~/openathena/marin-viewer` becomes the Radiology fork itself, so later upstream work
merges with `git merge upstream/main`. Marin-specific code lives in new directories and new Swift files
wherever possible, which keeps those merges small.

```
~/openathena/marin-viewer/
  DESIGN.md
  Package.swift, Sources/, Tests/, Makefile ...  # Radiology, plus the viewer's Swift code
  Sources/Radiology/Viewer/      # new Swift code: strip, diagrams, panel, notes, sidecar client
  Packages/ViewerCore/           # SwiftUI-free logic: diff rows, visibility, blame, wordbase models
  sidecar/                       # TypeScript: Agent SDK sessions, tools, poller, prep, lint, layout
  prompts/                       # system prompts, style rules, examples
  demo/                          # the HTML demo, its PR data, extract.py and smoke.js
                                 # (smoke.js: `npm i jsdom@24.1.3`, then `node demo/smoke.js demo`)
  marin/                         # clone of marin-community/marin over SSH (gitignored)
  wordbase/                      # its own git repo of markdown entries (gitignored here)
  state/                         # poller state and logs (gitignored)
```

Set-up order: `git init` in place, add `upstream` = `https://github.com/tqbf/radiology`, fetch, then
check out `upstream/main` into a new `main` branch. `DESIGN.md` and `demo/` do not collide with
Radiology's files. Clone Marin with `git clone git@github.com:marin-community/marin.git marin`. Use SSH
only (Marin's CLAUDE.md §9).

Builders read Radiology's own `AGENTS.md`, `CLAUDE.md` and `SWIFTUI-RULES.md` before changing Swift
code. Its `make check`, `make test` and `make run` stay the build entry points.

## 5. The app

### What changes in Radiology

| Area | Radiology | Viewer |
| --- | --- | --- |
| PR file display | Whole file, changed lines washed, Before/After toggle | Diffs first with inline deletions, expanders, Whole file toggle. Before/After stays as a menu action |
| Left sidebar | Changes / Files / Code Paths / Search | Code path (the viewer's steps) / Changes / Files (focused tree in PR review, Radiology's tree otherwise) / Search |
| Code paths | Pasted `file:function:description` steps | Steps from the preparation turn, each with several excerpts, resolved by name |
| Right side | Context inspector | Panel with Session / Review notes / Context tabs |
| Top | Toolbar | Toolbar plus the three-card strip |
| Windows | One window, one `AppModel` | Main window plus code-only secondary windows |
| Blame | None | Gutter from `git blame --porcelain`, cached per file and commit |

The reader changes are the largest part. Radiology's `ReaderTextView` (TextKit, 775 lines) draws one
file's text. The diff mode needs a row model: context, added, deleted and gap rows, plus inline note
rows, built from `git diff -U<whole file>`, the way `demo/extract.py` builds `lines`. It also needs the
same highlighting, caret, folding and ⌘-click behavior over that row model. Keep the existing reader for
Normal mode and add the diff mode beside it, without rewriting it.

Multi-window: a secondary window holds a reader only, with no sidebar, strip or panel. It shares the
main window's session store, so ⌘> in a secondary window adds a chip to the main window's session.
"Promote to session" in its menu forks the session and gives the window its own panel.
`AppModel` splits into a per-window reader model and a shared store (repository, PR, wordbase, sessions).

### Diagrams

Diagrams are data, laid out by the sidecar and drawn by the app with SwiftUI `Canvas`. The sidecar runs
elkjs (layered algorithm) and returns box and edge coordinates; the app draws boxes, groups, edges and
labels in the demo's style. The agent writes only nodes, edges and groups, never coordinates.

## 6. Data formats

All of these files live in the wordbase. Section 9 runs the app and the pipeline in parallel, so
these formats are fixed first.

### Wordbase entries

`wordbase/<repo path>.md` for a file, `wordbase/systems/<name>.md` for a subsystem (nesting allowed),
`wordbase/prs/<number>/` for a PR, `wordbase/reviewer.md` for how Mark reviews.

```markdown
---
kind: file                 # file | system | pr | reviewer
path: lib/shellbox/src/shellbox/http_service.py
commit: 01a8bb8f0bea2dde1de90274ed695c25147b9f06   # the code this description describes
updated: 2026-11-01T16:40:00Z
by: claude-opus-5-5 prep 10640    # model and run that wrote the layers
l1: Runs a loopback HTTP listener inside a machine and relays each request ...
l2: Frames are newline-delimited JSON checked by strict Pydantic models ...
l3:
  - First paragraph ...
system: shellbox           # file entries name their subsystem
---

## Symbols

### `_pump`
l1: ...
l2: ...

## Notes

- 2026-11-01 · 01a8bb8 · session 3f2a… · The relay's failure behavior under a stuck model endpoint ...
```

System entries add `members:` (paths and child systems), `uses:` and `used_by:` (other systems), and a
`diagram:` block in the diagram format below. The "In Marin" map comes from the `uses` / `used_by`
graph around the current system.

- The map has a box with the system's own name, and a box for every system in `uses` and
  `used_by`.
- A package such as `iris` has ten neighbours, which leaves no room for its own parts within 10
  boxes. One box may then stand for several neighbours, listing them under `systems:` (a list of
  names) and giving each one's `lib/<name>/` under `paths`. `check_fixture.py` counts a system
  listed there as having a box.

### PR outputs

`wordbase/prs/<n>/` holds:

- `pr.md`: front matter `head`, `base`, `merge_base`, `prepared_at`, `session_id`, and the layered
  description.
- `code-path.json`:
  `[{ "id": 1, "title": "...", "l1": "...", "l2": "...", "node": "spec", "excerpts": [{ "path": "...", "functions": ["ServiceEndpoint", "TaskSpec"], "lines": [45, 111] }] }]`.
  - `functions` lists one or more consecutive declarations, resolved by name against the head commit
    following Radiology's rule. The excerpt spans their union.
  - `lines` is a fallback, rewritten after each resolution. A whole-module excerpt uses
    `"functions": []` and keeps `lines`.
  - Radiology's text format can be exported for compatibility, one step line per declaration.
- `diagrams.json`:
  `{ "pr": Diagram, "steps": { "6": Diagram, ... } }`, where Diagram is
  `{ "layout"?: { "mode": "auto" | "grid", "direction"?: "RIGHT" | "DOWN" }, "nodes": [{ "id", "label", "sub", "step"?, "at"?: { "path", "function" }, "paths"?: [repo paths], "grid"?: { "col", "row", "span"? } }], "edges": [[from, to, label?]], "groups": [{ "label", "members": [ids] }] }`.
  - `paths` gives the files a box stands for. The app marks a box as touched when the PR changes
    one of them, and dims it when the PR changes none.
  - **Layout:** every diagram is drawn into a card of about 460×196 points (aspect 2.35).
    - In `auto` mode the sidecar runs ELK's layered algorithm with `elk.aspectRatio` 2.35 and
      `elk.layered.wrapping.strategy` `MULTI_EDGE`, so long chains wrap into rows.
    - In `grid` mode every node carries a `grid` cell (integer column and row, optional column span)
      and the sidecar scales the grid to the card. The agent never writes pixel coordinates.
    - The preparation prompt asks for at most 10 boxes per diagram. It asks for `grid` when the
      picture depends on placement: two sides of a boundary, a loop, or groups side by side.
- `notes.jsonl`, one review note per line:
  `{ "id", "path", "line", "side": "head|base", "commit", "severity": "high|medium|low|design", "status": "draft|approved|rejected|posted|resolved", "who", "l1", "l2", "github_comment_id"?, "created", "updated" }`.
- `files.json`: per changed file, the layered description of the change (the file-header text).

### Fixture

Step 0 of the build turns the demo's content into `wordbase/prs/10640/` and the matching file
entries. That content is the `PR`, `FILES`, `STEPS`, `FINDINGS`, `SUB`, `CTX` and `STEP_DIA`
constants in `demo/index.html`, with `demo/pr10640.json` as the diff data. The app is then built
against a real fixture before the pipeline writes anything, and the fixture doubles as the style
reference for generated text.

## 7. The sidecar

`sidecar/` is a TypeScript package on `@anthropic-ai/claude-agent-sdk`. The app starts it as a child
process and exchanges JSON lines on stdin/stdout. Every message has `type`, and requests carry `id`.

From the app:

- `session.open {scope: {pr} | {system} | {path}, resume?: sessionId, fork?: bool}`
- `session.send {session, text, chips: [{kind, path?, lines?, symbol?, commit, label}]}`
- `session.interrupt {session}`
- `session.close {session, propose_notes: true}`
- `notes.keep {session, notes}`
- `layout {diagram}` returns positioned boxes and edges
- `review.post {pr, notes}`
- `app.response {id, result}`

From the sidecar:

- `stream.delta {session, text}` and `turn.result {session, cost_usd, usage}`
- `ui.command {session, name: "focus_code_path" | "open_location" | "draft_review_note", args}`
- `app.request {id, name: "find_symbol" | "selection_context", args}` (app answers within 5 s)
- `notes.proposed {session, notes: [{target, text, commit}]}`
- `error {session?, message}`

**Sessions.** A session's cwd is a worktree at the PR head, created the way Radiology creates its review
worktrees. The wordbase is in `additionalDirectories`, and `settingSources: ["project"]` is set. The
system prompt is the `claude_code` preset plus `prompts/session.md`, which explains the viewer, the
chips, the wordbase path rule and the tools. Interactive sessions run on the `claude` login, so
`ANTHROPIC_API_KEY` is removed from their environment. Session ids per PR and system are stored in
`state/sessions.json`. Opening a PR resumes its preparation session.

**Tools** (in-process SDK MCP server):

- `focus_code_path`, `open_location`, `draft_review_note`: send a `ui.command` and return at once.
- `wordbase_entry(path | system | symbol)`: reads the entry and its linked entries. Given a symbol,
  it returns only that subsection.
- `find_symbol(name, commit)`: asks the app, which holds the SCIP indexes.
- `propose_notes(notes)`: used only in the closing turn.

**Closing.** `session.close` sends one more turn that asks for memories under the rules in
`prompts/memories.md` (what was learned, never bugs; cite the commit). The sidecar returns them as
`notes.proposed`. The app shows them with × buttons and sends `notes.keep` with the remaining notes
when Mark presses Done, opens another session, or closes the window or the app. The sidecar appends
kept notes to their entries and commits the wordbase with message
`notes: session <id> (<scope>)`.

**Posting.** `review.post` creates one pending review with `gh api` (line and side per note), submits
it, and records `github_comment_id`. It runs only after the app's confirm box. Posting to GitHub from
any other path is not allowed.

## 8. The poller and preparation runs

`cd sidecar && npm run poll` runs in the foreground in Mark's terminal and prints one line per action.
It stops on Ctrl-C. Each tick (default every 5 minutes, `--interval`) does the following.

1. **Update Marin.** `git -C marin fetch origin main` and `git merge --ff-only origin/main`. A failure
   prints an `ERROR` line and the tick goes on with the old `main`.
2. **Describe new commits.**
   - Take the commits between `state/main.json.described` and `origin/main`, and collect the files they
     changed, renamed or deleted.
   - Regenerate each changed file's entry at the new commit. Keep its notes, and mark notes about
     symbols whose code changed as `(code changed at <sha>)`.
   - Move entries on rename. Mark them `deleted: <sha>` on delete.
   - When a file's `l1` changes, queue its subsystem page for one refresh at the end of the tick.
   - `state/main.json` records the commit range each run covers and when the read started, so a crash
     resumes from the last covered commit.
3. **Prepare PRs.**
   - List open PRs that request Mark's review, and his own open PRs, with
     `gh search prs --repo marin-community/marin`.
   - A `gh` error is an error, never an empty list.
   - Any PR whose head SHA is new to `state/prs.json` gets a preparation run, two at a time.
   - A run fetches the PR the way Radiology does and builds SCIP indexes for base and head. It then
     opens the PR's session and sends the preparation turn (`prompts/prepare-pr.md`), which writes the
     section 6 outputs.
   - For Mark's own PRs, the turn also reads the Claude Code transcripts of the branch's sessions
     (`~/.claude/projects/*/*.jsonl`, matched on branch name or worktree path) and the Iris jobs they
     mention. Iris is reached through `uv run iris --cluster=marin job describe` from the Marin clone,
     following Marin's CLAUDE.md §4.
   - A new head SHA on a prepared PR resumes the same session with a short update turn. That turn
     revises the outputs and marks posted notes as resolved when the code they describe has changed.
4. **Print a summary line:** commits described, files regenerated, PRs prepared, cost of the tick,
   month-to-date cost. Print a `GAP` line when the time since the last tick exceeds twice the interval.

**Budget.** Background runs use the Console API key, so they draw on the plan's monthly API credits.
The poller paces spending so the month's credits are used up by the end of the month; leftover
credit is wasted capacity. When spending runs ahead of pace, it defers file regenerations (the queue
persists in `state/`) and still prepares PRs. Models:

- PR preparation: Opus 5.5.
- File and subsystem descriptions: start on Sonnet 5.5, then compare 20 entries against Opus 5.5
  under the style rules before settling.

**Generation passes.** Every description runs through `prompts/style.md` (the Mariven gist plus Marin's
`docs/dev-guide/writing-style/ai-writing-donts.md`, with the demo's descriptions as examples), then the
lint below. Subsystem pages and PR descriptions also get a cold-reader pass: a fresh session gets the
description and the code and lists claims it cannot check against the code. Failures are rewritten
once and then kept with a `lint:` field listing what still fails.

**Lint** (`sidecar/src/lint.ts`, unit-tested on bad and good sentences):

- em and en dashes;
- the gist's banned words;
- stock contrast (`X, not Y`, `not just`, `rather than` without a comparison);
- counting openers ("Three ...:");
- signposts;
- headings that start with question words;
- bold labels.

**Context for descriptions.** A file described alone cannot say who calls it or what part it plays,
so a description run covers a unit with its surroundings. A unit is one source directory under
`lib/`, split into slices only when its own files and tests pass the budget. Every prompt stays
within 256K input tokens (o200k count, which matches GPT-6.1 Terra's billing), under Terra's 272K
price step. Everything in the prompt is full source, with no cuts or signature-only files. It is
filled in this order:
1. the unit's own files;
2. the package README;
3. the subsystem page, existing entries and, on a regeneration, the diff;
4. the tests that exercise the unit;
5. neighbours, as many full modules as fit: modules the unit imports and modules that import it,
   from the whole checkout except `vendor/` (`lib/`, `experiments/`, `scripts/`, `infra/`, root
   `tests/`). When they don't all fit, the choice goes round-robin across packages and prefers
   non-test code, and the prompt lists what was left out.

Test directories are not units: tests are not systems. Each test file under `lib/` belongs to the
unit it imports the most names from, and that unit writes the test a one-sentence `l1` and nothing
more. Tests that import no described code get `l1`s in one batch at the end.

The run writes an entry for every file in the unit. The poller's regenerations take the same shape:
a changed file is described with its unit, and unchanged siblings keep their entries unless the
change alters what they do. A changed test is rewritten by its owner unit, or in the batch.

**First full pass.** Decided 2026-11-02: GPT-6.1 Terra through OpenRouter on the flex tier, at
reasoning effort medium. The pass runs from the sidecar on this machine, many requests at a time.
It needs no Iris job, because Terra is an API. Estimated at about $17 for 184 prompts and 23.6M
input tokens at Marin `1d274b5` (`state/reports/describe-comparison.md` has the comparison
against Sonnet 5.5, Opus 5.5 and GLM-5.3, and the estimate). The pass runs in two rounds:
1. Every source unit, then the orphan test batch. Units can run in any order, since each prompt
   carries its callers' full source.
2. Subsystem pages, written from the finished file entries with source excerpts, then the cold
   reader. The model is undecided; Mark is leaning toward Fable 5.1.

There is no round that re-describes units once their importers have entries (dropped
2026-11-02). The pass verifies completion by counting files with entries against files expected,
and resumes by skipping units whose entries cover their files at the pass's commit. GLM-5.3 stays
available for this project without further approval (2026-11-01), under the fleet's shed rule.
Until the pass has run, entries appear only for files that commits or PRs touch, and the poller
fills them in.

## 9. Building it with subagents

Each workstream owns its directories. All of them read sections 6 and 7 as the contract.

| Workstream | Owns | Done when |
| --- | --- | --- |
| 0. Fork and fixture | repo set-up, `marin/`, `wordbase/prs/10640/` | `make check` passes on the fork. The fixture files match section 6 and hold the demo's content |
| 1. Diff reader | reader diff mode, blame, note gutter | #10640 at `01a8bb8` shows the demo's rows, gaps, expanders, blame and inline notes. Row-model tests pass |
| 2. Shell | strip, diagrams, left tabs, right panel, chips, menus, ⌘>, windows | Every interaction in `demo/smoke.js` works on the fixture in the app |
| 3. Sidecar | `sidecar/` sessions, tools, protocol, layout, posting | Protocol tests pass. A live session on #10640 answers a chip question and issues `focus_code_path` |
| 4. Pipeline | poller, prep, description runs, prompts, lint | One tick on a quiet `main` and one on a new commit both print correct summaries. Preparing a live review request (such as #10330) writes valid section 6 files |
| 5. First pass | `npm run first-pass` on GPT-6.1 Terra flex through OpenRouter | Every Python file under `lib/` has an entry whose lint result is recorded, and a count of inputs seen equals inputs expected |

Workstream 0 runs first. Workstreams 1, 3 and 4 then run in parallel against the fixture.
Workstream 2 starts once 1 shows rows. Agents run Swift checks with Radiology's `make check` and
`make test`, and sidecar checks with `npm test`.

Mark checks UI work against the demo: the same PR, the same screens, side by side. A builder reports
what it ran, what passed, and what differs from the demo.

Rules for builders:

- Never post to GitHub or push without Mark's confirmation in the session. GLM-5.3 jobs for this
  project are pre-approved; other cluster jobs need confirmation.
- Keep Radiology's code changes small and in new files where possible, so upstream merges stay easy.
- Python goes through `uv run` (Marin's CLAUDE.md §1).
- UI captures and interactive checks happen on the built-in Retina display, through
  `tools/viewer-ui.swift`, never on the external ultrawide (1x, and Mark's other work is there).
- Commit messages, here and in the wordbase, follow Marin's
  `docs/dev-guide/writing-style/pull-requests.md`: an imperative title of at most 72 characters, plain
  paragraphs that lead with what changed, and no `Co-Authored-By` or other attribution trailers.
- The GitHub API budget is shared. Prefer `git` and `raw.githubusercontent.com`, and have the poller
  print its `gh` call count per tick.
