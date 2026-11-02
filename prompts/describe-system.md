# Describe a subsystem

<!-- The subsystem page of DESIGN.md sections 6 and 8, written by `npm run system-pages` and by the
poller's subsystem refresh. It runs with no tools, so the rendered prompt holds everything the model
needs. Fill every {{placeholder}}; {{style}} takes the full text of prompts/style.md. Strip this
comment. -->

You write the subsystem page for `{{system}}`, the package at `lib/{{system}}/` in the Marin
repository (`marin-community/marin`), at commit `{{commit}}`. The Marin viewer shows the page in its top
strip when a reader opens the package: the description, the package's place in Marin and its own map.
Maps of Marin show the page's `l1` beside the package. This message holds everything you need; you have
no tools.

## Inputs

The inputs follow this prompt, each between a `=== BEGIN <name> ===` line and an `=== END <name> ===`
line:

1. `FILES`: the wordbase description of every source file in the package, by path: its `l1` sentence
   and, when it has one, its `l2` paragraph.
2. `TESTS`: the `l1` sentence of every test file in the package, by path.
3. `README`: the package README, in full, or `none`.
4. `EXCERPTS`: the source of the package's main entry points: its top-level `__init__.py`, the
   modules its `pyproject.toml` names as scripts, and the modules other packages import most. A file
   too long to give in full is given as its definition lines.
5. `NEIGHBOURS`: each Marin package this one depends on (`uses`) or that depends on it (`used_by`),
   read from the packages' `pyproject.toml` files, with that package's one-sentence description and
   where the sentence came from.
6. `LEFT OUT`: inputs the prompt had no room for, or `none`.
7. `EXISTING`: the current page's layers, or `none`.

## Page

- `l1`: one sentence about what the package lets a caller do.
- `l2`: one paragraph on the mechanism: the entry points a caller uses, by their code names, the
  main types and the order of the calls. Say which Marin packages it builds on and which build on it,
  and for what, where the inputs show it.
- `l3`: a list of paragraphs, for a package with more than about 20 files: secondary features,
  backends or variants, limits and their values, and the dependents that rely on particular behavior.
  Give each paragraph one topic.

Claim nothing beyond what the inputs show. When `EXISTING` holds a page, treat it as an earlier draft:
keep what the inputs still support, and correct what they do not.

## Map

`diagram` is the package's map in the strip's "In Marin" card, about 460 by 196 points. Write only
boxes, edges and grid cells; the viewer lays it out and draws it.

- Use `"layout": { "mode": "grid" }`, at most 10 boxes, at most 4 columns (`col` 0 to 3) and 3 rows
  (`row` 0 to 2), one box per cell.
- One box has the id `{{system}}` and stands for the package itself.
- Every package listed under `NEIGHBOURS` needs a box. Give a neighbour's box the package name as its
  id and `"paths": ["lib/<name>/"]`. When the neighbours do not all fit, one box may stand for
  more than one. Give that box its own id, `"systems"` listing their names, and the `lib/<name>/`
  path of each.
- Fill the remaining boxes with the package's main parts: subpackages, modules or groups of modules,
  each with the `paths` it stands for. A directory path ends in `/`. Every path must appear under
  `FILES` or be a directory that holds such a file.
- Put the packages that use this one in the top row, this package and the packages it uses in the
  middle row, and its own parts in the bottom row. A row that has nothing to show may stay empty.
- A box has a short `label`, such as `Iris` or `Backends`, and a `sub` of one to four words.
- Edges are `{ "from", "to", "label"? }`: from each dependent to this package, from this package (or
  the part that does the calling) to each package it uses, and from this package to its parts.

A box is `{ "id", "label", "sub", "paths"?, "systems"?, "grid": { "col", "row", "span"? } }`.

## Output

Reply with a single JSON object and nothing else:
`{ "l1": "...", "l2": "...", "l3": ["...", "..."], "diagram": { "nodes": [...], "edges": [...] } }`.
Every reply includes `diagram`, a small package included: the strip draws nothing without it. Leave
out `l3` when the package does not need it. Put code names in backticks.

## Style

Write every text field under these rules.

{{style}}
