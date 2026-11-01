# Preparation turn

This turn prepares PR #{{number}} of `marin-community/marin` for Mark's review before he opens it. Your
working directory is a worktree at the PR's head `{{head}}`. The base is `{{base}}` and the merge base
is `{{merge_base}}`. The viewer holds SCIP indexes for base and head, which `find_symbol` queries.

Write the PR's outputs into `{{wordbase}}/prs/{{number}}/`, following DESIGN.md section 6. Every text
field follows `prompts/style.md`. Mark reads this material instead of the raw diff, so each claim
must hold at the head commit.

## Read first

1. `gh pr view {{number}} --repo marin-community/marin --json title,body,author,state,files,reviews,comments`
   and the review threads with `gh api repos/marin-community/marin/pulls/{{number}}/comments`. The
   GitHub API quota is shared by every job on the account: make at most 10 `gh` calls in this turn
   and report the count at the end. Prefer `git` for anything in the worktree.
2. `git diff {{merge_base}} {{head}} --stat`, then the diff of every source file. Read tests after
   the source that they cover.
3. The wordbase entries for the subsystems and files that the PR changes, through `wordbase_entry`, and
   `wordbase/reviewer.md`.
4. For Mark's own PRs, the Claude Code transcripts of the branch's sessions
   (`~/.claude/projects/*/*.jsonl`, matched on branch name or worktree path) and the Iris jobs that they
   mention, through `uv run iris --cluster=marin job describe <job>` from the Marin clone. Record
   what the transcripts establish about intent and testing in `l3` of the PR description.

## Outputs

### `pr.md`

Front matter with `kind: pr`, `number`, `title`, `author`, `state`, `head`, `base`, `merge_base`,
`prepared_at` (UTC, ISO 8601), `session_id`, `commit` (the head), `updated`, `by` (model and run), and
the layered description:

- `l1`: what the PR lets a caller do, in one sentence.
- `l2`: the mechanism in one paragraph, with the main types and functions in call order.
- `l3`: paragraphs for secondary features, limits with their values, what the PR leaves out, related
  PRs and issues, and Mark's review history on this PR. Address Mark as "you" when reporting his
  earlier comments, and give the share of them that still points at code in the diff.

### `code-path.json`

The code path is an ordered trace through the change, in reading order. It
answers the question "how does this PR's main feature run, from the caller's entry point to
teardown?"

Investigation:

- Find the entry point that a caller uses. Follow control flow and data flow through concrete call sites,
  and stop at the boundary of the change.
- Read the implementation of every excerpt that you cite. Verify that each path exists at the head and
  that each `function` is a real declaration there. Never guess a symbol, and never use a call-site
  spelling in place of the declaration.
- Include the connecting steps that explain how execution passes from one stage to the next. A trace
  may return to a function or file; keep execution order.
- Write branches as branches: "If the policy is DENY...", "On failure...". Do not imply that
  mutually exclusive branches run in sequence.
- Distinguish proven direct calls from registration, callbacks, generated dispatch and inferred
  links. Put uncertainty and configuration dependencies in the step's `l2`. Do not invent a callee to
  bridge a gap.
- For code outside the worktree or generated at build time, cite the last verified call site and
  describe the boundary in `l2`.
- Prefer a coherent end-to-end trace over an inventory of symbols. Each step says what the code does
  and why a reader needs it at that point.
- Tests become steps only when test infrastructure is the change.

Each step is an object:

```json
{ "id": 1, "title": "Describe the task", "l1": "...", "l2": "...", "node": "spec",
  "excerpts": [{ "path": "lib/shellbox/src/shellbox/task.py", "functions": ["ServiceEndpoint", "ReadinessProbe", "ContainerSpec", "TaskSpec", "single_container_task"], "lines": [45, 111] }] }
```

- `id`: 1 to n in reading order.
- `title`: a short imperative phrase, such as "Relay HTTP to the host".
- `l1`: one sentence. `l2`: a paragraph, left out when `l1` says enough.
- `node`: the id of this step's box in the PR diagram. Every step needs a box.
- `excerpts`: the code to read for this step, in reading order, usually one to three.
  - `path`: repository-relative, never absolute and never containing `..`.
  - `functions`: every declaration that the excerpt spans, in source order. They must be consecutive
    declarations with the same parent: neighbouring methods of a class, or neighbouring top-level
    functions, classes and assignments of a module. Give each one by its name at the head commit, and
    qualify a method with its class (`Task.close`, `LocalMachineFactory.create_task`). Module-level
    assignments count as declarations (`_TIMED_PROBE`). Each name must match exactly one declaration
    in the file; qualify it further when it does not.
  - Use `"functions": []` only for an excerpt that covers the whole module.
  - `lines`: the first and last line of the excerpt at the head commit. The viewer resolves
    `functions` first, shows their union and rewrites `lines` to match. Choose `functions` so that
    their union is the code that you mean; the check script reports an excerpt whose `lines` differ.

The demo PR, #10640, changes 30 files and uses 8 steps. Use as many steps as the change requires.

### `diagrams.json`

```json
{ "pr": Diagram, "steps": { "6": Diagram } }
```

A Diagram is
`{ "layout": { "mode": "auto" | "grid", "direction"?: "RIGHT" | "DOWN" }, "nodes": [...], "edges": [[from, to, label?]], "groups": [{ "label", "members": [ids] }] }`.
Each node has `id`, `label` and `sub`. It may also have:

- `step`: the step that a double-click on the box opens;
- `at`: `{ "path", "function" }`, the code that a click on the box opens;
- `paths`: the repository files or directories that the box stands for. The viewer highlights a box
  when the PR changes one of its paths, and dims it otherwise. Fill `paths` on every box
  that stands for code;
- `grid`: `{ "col", "row", "span"? }`, the box's cell in grid mode. `col` and `row` count from 0, and
  `span` is the number of columns that the box covers.

The viewer draws each diagram into a card of about 460 by 196 points, a width 2.35 times the height.
Give a diagram at most 10 boxes, and in grid mode at most 4 columns and 3 rows. Write no pixel
coordinates.

- Use `"mode": "grid"` when the picture depends on placement: the two sides of a process or network
  boundary, a loop, or groups side by side. Give every box a cell, and leave no two boxes in the same
  cell. Use 3 columns where the picture allows it, and `span` only when a box belongs above two
  others. Each column is as wide as its widest box, so boxes need no equal widths. The demo's step 6
  diagram, for example, puts the guest helper in columns 0 and 1 and the host process in columns 2
  and 3, with the request loop running down one side and back up the other.
- Use `"mode": "auto"` for a chain or a tree. The sidecar lays it out with ELK and wraps long chains
  into rows. Leave out `grid`.
- The PR diagram (`pr`) is required. Give it a box for each component that the PR changes, with
  `step` on each box that a step uses. `label` is the code name or a short phrase; `sub` is two to
  four words, such as "bounded frames".
- Draw edges in the direction of data or control flow, and label an edge only when the label adds a
  fact ("loopback", "peer").
- Use groups for process, machine and network boundaries, such as "Bubblewrap task, external network
  denied".
- Step diagrams are optional. Draw one for a step that crosses a process boundary or has more than
  four moving parts. Give `at` to every box that stands for code in the repository: the narrowest
  declaration that the box describes, with the same name rules as excerpts. When a box's label is a
  declaration name, such as `_expire`, anchor it to that declaration, never to a line that calls it.
  Boxes for outside actors, such as the host handler or a guest client, have no `at`.

### `files.json`

An object keyed by repository path, with `{ "l1", "l2"? }` for each changed source file. The text
describes what the file does in this change; the viewer shows it in the file's sticky header. Give
`l2` for the files where a reviewer spends the most time. Skip lockfiles and generated files.

### `notes.jsonl`

Each line holds a review note:

```json
{ "id": "f1", "path": "...", "line": 133, "side": "head", "commit": "{{head}}", "severity": "medium",
  "status": "draft", "who": "review session", "l1": "...", "l2": "...", "created": "...", "updated": "..." }
```

- Draft a note for each bug, race, missing check or design risk that you find while reading. `l1` gives the
  failure in one sentence; `l2` gives the sequence of events that produces it, the evidence and a
  direction for a fix.
- Severity is `high` for data loss, security or a crash on a common path, `medium` for a failure
  under load or a plausible fault, `low` for a poor error or a small cost, and `design` for a question
  about structure.
- Import Mark's earlier review comments as notes with `who: "you"`, status `posted` and their
  `github_comment_id`. Set a note to `resolved` when the head commit has changed the code that it describes,
  and say what changed in `l2`.
- Write notes only to this file. Do not post anything to GitHub.

## Check before finishing

Run `uv run --with pyyaml ~/openathena/marin-viewer/prompts/check_fixture.py --wordbase {{wordbase}}`
and fix every failure it reports. It checks the required keys, the enumerations, every declaration
name against the head commit, every step's `node` against the PR diagram, the grid cells and the
box paths.

End the turn with a short record for the panel: the files read, the outputs written, the number of
steps, diagrams and draft notes, and the `gh` call count.

## Update turns

When the PR gets a new head, this session resumes with the new head and base. Read the diff between
the old and new heads, then revise the outputs: rewrite the steps and descriptions that the new commits
change, re-resolve every declaration name, and mark posted notes `resolved` when the code that they describe has
changed. Keep the ids of steps and notes that still apply.
