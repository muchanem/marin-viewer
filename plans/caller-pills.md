# Caller identity pills and cycle repair

Implemented 2026-10-11 following the user's feedback that `launch` could appear
repeatedly in one chain, then their request to color each entry by a hash of
the method name and the file containing it.

## Identity and appearance

Each caller is a native button with a capsule background containing its method
name, filename and call-site line. Branch arrows and deep-level markers remain
outside the capsule; boundary notes remain beneath it. Activating any part of
the pill uses existing caller navigation and exact-caret Back behavior.

`CallTreePalette` provides twelve dynamic system colors, in fixed order:
blue, teal, purple, orange, pink, indigo, green, cyan, brown, mint, red, yellow.
FNV-1a 64-bit over the method's UTF-8 name, a NUL separator, and its full
repository-relative file path selects a palette slot. It does not use Swift's
process-randomized Hasher. The same method/file pair keeps the same color across
call sites, branches, sorting, reference expansion, appearances and relaunches.
Different same-named methods in different files can receive different colors.
Finite palette slots can collide; text and full path help remain the identity.

Light/dark fill opacities are 12%/24%, with a 30%/50% thin outline. Increased
contrast or Differentiate Without Color strengthens the outline to 75%; the
latter also increases its width to 1.5 points. Text retains dynamic primary/
secondary system styles rather than taking the identity hue. Existing semantic
callout monospace semibold names and caption regular filenames/tabular line
numbers retain the inspector hierarchy. Capsule padding is 12 horizontal and
6 vertical points. No new fixed font sizes or animations.

Applied swiftui-pro before and after the changes, plus macos-design and
typography-designer. See [reference-call-trees.md](reference-call-trees.md) for
the broader traversal and resizable pane contract.

## Cycle repair

Previously the traversal stopped at a repeated semantic identity but still
rendered that duplicate as a terminal caller row. It now checks incoming callers
against both semantic identities and canonical declaration-name locations
before enqueueing them. A repeated callable is omitted and the preceding entry
gets **Recursive branch stopped**. Unrelated sibling paths and shared ancestors
on separate branches remain. Distinct functions with the same display name are
preserved; deduplication never uses spelling alone.

Self-recursion, `launch -> relay -> launch`, sibling continuation and distinct
same-named functions have regressions. The 270-level continuation and existing
navigation/divider tests continue to run. Fixed portable palette assignments
cover same names in different files, non-ASCII names and field-boundary cases.

## Visual checks

Actual production rows backed by the branching index fixture render at
220/280/420 points in light and dark; files are
`build/callers-pill-review/{light,dark}-*.png`. Repeated `entry` nodes on separate
branches have matching brown pills, while distinct method/file pairs show the
selected palette hues. Narrow names truncate inside the capsule; filename and
line metadata remain legible. To reproduce:

```sh
RADIOLOGY_CALLER_RENDER_DIR="$PWD/build/callers-pill-review" swift test --filter ContextInspectorLayoutTests
```

Desktop automation was retried after the user said it should work. This session
still reports `Module not found: @oai/sky`, including after resetting the Node
kernel. No live UI actions or user-reader restart were performed; mouse checks
remain unverified. Logs are `/tmp/radiology-callers-pills-{targeted,tests,build}.log`.

Fresh full suite: **263 tests /55 suites**, all pass. Compile, signed build,
strict deep codesign, empty-environment `/tmp` resource check (8 grammars,
37 queries,3 indexing scripts), and `git diff --check` pass. Signed executable
built **2026-10-11 13:47:46 CDT**. Compile log:
`/tmp/radiology-callers-pills-check.log`. Work remains local/uncommitted.
