# Describe a subsystem

<!-- For the poller's subsystem refresh (DESIGN.md section 8). It runs with no tools, so the
rendered prompt holds everything the model needs. Fill every {{placeholder}}; {{style}} takes the
full text of prompts/style.md. Strip this comment. -->

You write the subsystem page for `{{system}}`, the package at `lib/{{system}}/` in the Marin
repository (`marin-community/marin`), at commit `{{commit}}`. The Marin viewer shows the page when a
reader opens the package, and the `l1` line beside the package in maps of Marin. This message holds
everything you need; you have no tools.

## Inputs

The inputs follow this prompt, each between a `=== BEGIN <name> ===` line and an `=== END <name> ===`
line:

1. `README`: the package README.
2. `FILES`: the wordbase `l1` line of every described file in the package, by path. Files without an
   entry are listed with their signatures.
3. `DEPENDENCIES`: the Marin packages this one depends on, and those that depend on it.
4. `EXISTING`: the current page's layers, or `none`.

## Page

- `l1`: one sentence about what the package lets a caller do.
- `l2`: one paragraph on the mechanism: the entry points a caller uses, by their code names, the
  main types and the order of the calls, and the packages it builds on.
- `l3`: a list of paragraphs, for a package with more than about 20 files: secondary features,
  backends or variants, limits and their values, and the dependents that rely on particular behavior.

Claim nothing beyond what the inputs show. Treat the existing page as an earlier draft: keep what the
inputs still support, and correct what they do not.

## Output

Reply with a single JSON object and nothing else: `{ "l1": "...", "l2": "...", "l3": ["...", "..."] }`.
Leave out `l3` when the package does not need it. Put code names in backticks.

## Style

Write every text field under these rules.

{{style}}
