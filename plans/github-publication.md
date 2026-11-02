# GitHub publication of the accumulated reader work

## 2026-10-31 — All local changes for direct publication to main

The user explicitly requested: "bundle up all the local changes and push them
to main on github". The starting `codex/toggle-current-function`, local `main`
and freshly fetched `origin/main` all pointed to `6d446b9`. This batch can be
committed directly on `main` and published through a normal fast-forward push;
no PR merge or force push is needed. The AGENTS.md prohibition on agent PR
merges remains in effect.

The snapshot includes current-function folding, Files navigation/reveal,
configurable inspector panes, Rust trait implementations, C/C++ syntax and
compiler indexing with best-effort fallback, seL4 configuration-union indexing,
TOML indexing personalities, persistent Code Paths in the left sidebar,
automatic destination expansion, keyboard help, test fixtures and all related
documentation. All nonignored local changes are included. Generated build
outputs, caches and the inactive nested `repo/` retain their ignore rules.

The newest PROGRESS.md entry records publication-time verification and its
known test exclusion. Earlier feature entries retain their detailed native UI
and real-data evidence; no implementation changes are made by this publication
round. The October 11 publication below is historical.

## 2026-10-11 — Previous publication through PR #1

User authorized publishing all current workspace changes on 2026-10-11.
Repository: [tqbf/radiology](https://github.com/tqbf/radiology), private.
Branch: `codex/reader-review-and-bookmarks`; base: `main` at `2e02ae3`.
GitHub's main matched the local base before publication. The user then explicitly
authorized merging this batch to main, superseding the earlier no-agent-merge
instruction for this publication. AGENTS.md is retained for future tasks.

**Published and merged:** [PR #1](https://github.com/tqbf/radiology/pull/1),
merged on **2026-10-11 at 19:53:25 UTC / 14:53:25 CDT**. Feature commit:
`3b8f7f53170c6e4134f4f5bf639b1b81bbd7ffdc`. Merge commit:
`dfc877a1734cca28543918273ea0a71825f42232`.

All 264 changed files in the accumulated snapshot are now on GitHub main.
GitHub reported the PR mergeable/CLEAN before the merge and MERGED afterward;
the merge was pinned to the exact published head commit. Local main was
fast-forwarded to the confirmed GitHub merge. A documentation follow-up records
this final status. The review branch is retained; future tasks should start
from main. No force push, viewed-repository mutation, or reader restart.

## Included scope

All source, tests, resources, artwork and documentation changed since the initial
published baseline: PR review/refresh and Before/After navigation, Critical Lens,
caret-driven context, incoming caller trees and identity pills, repository/PR
bookmarks, Kotlin semantic indexing, source/test filters, session restoration,
outline/gutter/breadcrumb/toolbar/sidebar refinements and native app icon/build
resource packaging. `RADIO.png` is the supplied source artwork; the new Kotlin
SCIP file is a committed test fixture with its source project/provenance.

Generated app bundles, compiler outputs, screenshots and the inherited inactive
`repo/` starter remain under the existing ignore rules. No viewed tkos bytes or
user-reader state are part of the Git snapshot.

## Validation used for this snapshot

The preceding bookmark round validated the entire current package: **269 tests
in 57 suites**, `make check`, signed `make build`, strict deep codesign and an
empty-environment `/tmp` resource probe (8 grammars/37 queries/3 indexing scripts).
Signed executable built **2026-10-11 14:41:15 CDT**. No implementation changed
between those gates and publication; this publication round updates metadata
documentation and runs Git whitespace/staging checks. Native hosted divider
tests and light/dark component renders pass. Physical drag/menu/keyboard checks
remain unverified because desktop automation is unavailable in this session.

The Kotlin SCIP fixture contains protobuf bytes that Git initially classified
as text and reported as trailing whitespace. `.gitattributes` marks all `.scip`
fixtures binary, preserving their bytes and preventing text transformations.
No fixture contents were edited.

The newest PLAN/PROGRESS/handoff publication entries supersede earlier feature
rounds' statements that changes were local and uncommitted. Earlier evidence
and manual acceptance limits remain historical records.
