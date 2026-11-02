# The poller and preparation pipeline

DESIGN.md section 8 says what the poller does. This page records how `sidecar/src/pipeline/` does it,
what was measured on 2026-11-01, and where the build departs from the design.

## Running it

```bash
cd sidecar && npm run build
npm run poll                         # foreground, one tick every 300 s, Ctrl-C stops it
npm run poll -- --once               # one tick
npm run poll -- --once --dry-run     # list what the describe step would do and the PRs; no model, no state change
npm run compare                      # the 20-file description comparison
```

The paths come from `sidecar/src/config.ts`: `MARIN_VIEWER_MARIN`, `MARIN_VIEWER_WORDBASE`,
`MARIN_VIEWER_STATE` and `MARIN_VIEWER_ENV_FILE`, which default to the directories beside the fork.
Background runs read `CLAUDE_API_KEY` from `.env` and pass it to the SDK as `ANTHROPIC_API_KEY`. GLM runs
read `GLM_API_TOKEN` and `GLM_BULK_TOKEN` from the environment or from
`~/openathena/glm-infer/glm_{api,bulk}_token.txt`.

Flags: `--interval`, `--monthly-budget` (default $200), `--max-tick-usd` (default $10), `--backend
claude|glm` and `--model` for descriptions, `--pr N` (repeatable), `--max-preps N` (default 2 a tick; 0
lists PRs only), `--prep-budget` and `--prep-effort` for the Opus run, `--no-prs`, `--no-describe`,
`--reset-described <rev>` (records `<rev>` as described before the tick) and `--describe-to <rev>`
(describes only through an ancestor of main).

## A tick

`Poller.tick` in `pipeline/poller.ts` runs the steps in order. Each step catches its own failure,
prints `ERROR <step>: <message>`, counts it in the summary and lets the tick go on.

1. **Update Marin.** `MarinRepo.updateMain` refuses unless the clone is on `main`, then runs `git fetch
   origin main` and `git merge --ff-only origin/main`. Nothing else in the pipeline checks out, resets
   or writes in the clone.
2. **Describe new commits.** The first tick with no `state/main.json` records the current main and
   describes nothing. Later ticks take `git diff --name-status -M` over `described..main`, limited to
   `lib/**/*.py`.
   - Deletions set `deleted: <sha>` on the entry. Renames move the entry file.
   - The other changes, plus any deferred queue, are grouped by directory into units. Each unit is one
     model call (`describe.ts`) with one rewrite when the reply fails the schema or the lint.
   - A unit whose new `l1` lines differ, or whose package has no page yet, queues its subsystem page
     (`systems.ts`). Each page gets one cold-reader pass and one rewrite.
   - `check_fixture.py --entry` validates every entry written. The wordbase is then committed as
     "Describe N files changed on main through sha7".
   - `main.json` records `in_progress` (range and read start) before the work and `described` plus
     `last_run` after it, so a crash resumes from the last covered commit.
3. **Prepare PRs.** `searchPrs` makes two `gh search prs` calls (review-requested and author).
   `fetchHeads` makes one `git fetch` of `refs/pull/<n>/head` for every listed PR into
   `refs/viewer/pr/<n>`, so head SHAs cost no API calls. A PR whose head differs from both `head` and
   `failed_head` in `state/prs.json` is due. Up to `--max-preps` of them run, two at a time.
4. **Summary line**, also appended to `state/poller.log`:
   `tick <time> · main <sha7> (+N fetched) · described C commits: F files in U units (K kept) · systems S · PRs P prepared, X failed, W waiting of L listed · cost $ · month $ of $budget (pace $) · gh N calls · E errors · T s`.
   A `GAP` line comes first when the last tick ended more than two intervals ago.

## Description context

`units.ts` `buildContext` assembles one prompt per unit from `prompts/describe-unit.md`:

- `SOURCE` blocks for the targets in full, and for siblings in full while the total stays under 70% of
  400,000 characters. The siblings past that come as signatures only.
- The package README, cut at 20,000 characters.
- `NEIGHBOURS`: up to 30 modules that the unit imports or that import it, each with its wordbase `l1`
  and its signatures. The import graph comes from one `git grep` per commit, resolved through
  `ModuleIndex` (src layout, relative imports, `from pkg import submodule`).
- `SUBSYSTEM` (the package page) and `EXISTING` (the targets' current entries).
- `DIFF` of the range for the targets, cut at 40,000 characters.
- `TARGETS`: the files that need entries. The model may answer `{"keep": true}` only for a target that
  already has an entry.

`describe.ts` checks the reply with zod and then for missing or extra keys, `keep` without an entry and
multi-sentence `l1`. It lints every text field with `sidecar/src/lint.ts`. `buildEntry` keeps the
entry's notes, preamble and other sections, and marks notes about changed symbols `(code changed at
sha7)`. Hits that survive the rewrite go in the entry's `lint:` field.

The Claude backend sets top-level `cache_control`, so a rewrite turn reads the unit context from the
cache. On the levanter tests unit, a reply plus rewrite came to $0.745 without caching and $0.520 with it
(365K input tokens). A call that needs no rewrite pays the 25% cache-write premium.

## Preparation runs

`prepare.ts` `preparePr`, per PR:

1. `ensureWorktree` checks out the fetched head, detached, in `state/worktrees/pr-<n>`.
2. `fetchPrData` makes `gh pr view` and one paginated `gh api` call for review comments. `attachments`
   adds them to the prompt as `PR METADATA` and `REVIEW COMMENTS` and, for Mark's own PRs, `markContext`: up to 4 matching
   Claude Code transcripts at 12,000 characters each, and `iris job describe` for up to 4 jobs they
   name. The agent itself makes no `gh` calls.
3. The prepare turn (or an update turn that resumes the recorded session on a new head) runs on Opus
   5.5 through `BackgroundSessions`, at effort high with `maxBudgetUsd`. `prepPolicy` lets Write and
   Edit write only under `wordbase/prs/<n>/`. It lets Bash run read-only commands and the exact check command
   (plus `--strict`), and denies `gh`, subagents, web tools and the viewer's UI tools.
4. `validatePrOutputs` checks the five section 6 files with zod. It also checks that the head matches,
   that there are at most 10 boxes per diagram on a 4 by 3 grid, and that boxes with `at` carry
   `paths`. It lints every text field except Mark's own notes. `runChecker` runs `check_fixture.py
   --strict-boxes --pr <n>`. Failures go back in one fix turn.
5. A Sonnet 5.5 cold reader (read-only Agent SDK query in the worktree) checks the PR description
   against the code. Its gaps go back in one rewrite turn, followed by a fix turn if the rewrite broke
   validation and none was used yet.
6. Lint hits that remain go in `pr.md`'s `lint:` field. The wordbase is committed as "Prepare PR #N at
   sha7 for review". `prs.json` gets `prepared`, `invalid` (outputs kept, `failed_head` set so the
   same head is not retried every tick) or `failed`.

Each run logs to `state/runs/pr-<n>-<sha7>.log`.

## State

`state/` holds `main.json`, `prs.json`, `queue.json` (deferred regenerations), `spend.jsonl` (one line
per model call: kind, run, model, cost, tokens), `poller.log`, `runs/`, `worktrees/` and `reports/`.
Corrupt state files throw. They never reset to empty.

**Budget.** `paceUsd` is the monthly budget times the elapsed fraction of the month. When the
month-to-date spend from `spend.jsonl` is ahead of pace, the describe step moves its regenerations to
`queue.json` and PR preparation goes on. `--max-tick-usd` stops starting new units in a tick once it
is spent.

## GLM-5.3

`GlmBackend.gate` reads `GET /health` and needs `workers.bulk >= 1`. It then reads
`/admin/engines/metrics` with the primary token and applies the shed rule in its strict form. The rule
trips on a median node KV above 0.70, any node above 0.85 with requests waiting, or preemptions above
the highest count read so far. A non-200 or a shed reason is a hold: it polls every 30 s for up to 10 minutes
(5 in `compare`), then fails with `FleetHold`. A refused connection raises `TunnelDown`, which means the
port-forward died while the fleet may be fine. Completions go to `/v1/chat/completions` with the bulk token. The gate never sends a
completion.

## Measured on 2026-11-01

All on Marin main `1d274b5`. Costs come from `turn.result` and API usage, as recorded in `state/spend.jsonl`.

- Describe tick (Sonnet 5.5, `--describe-to 41a4198` over 3 commits, 4 changed files in levanter and
  rigging): 4 units, 2 new subsystem pages, $2.80 without caching, 110 s. All 4 units needed a rewrite.
  A rerun with caching cost $1.49 and kept one entry unchanged (`keep`, 33 output tokens). The units ran
  197K to 401K context characters at about 2.35 characters per token.
- PR preparation (#10330, Opus 5.5 effort high): prepare turn $2.86, fix turn $0.11, cold reader
  (Sonnet 5.5) $0.11 with 1 gap, rewrite turn $0.11. Total $3.19 in 525 s. The run produced 15 steps,
  3 diagrams (10, 5 and 8 boxes), 11 review notes and 21 file descriptions, with no validation
  failures, no lint hits and a clean `check_fixture.py --strict-boxes --pr 10330`. Its high-severity note
  says `calibforge_captured_fixtures.main` reads a `public_fixture_roots` key that nothing in the PR
  writes. `rg` confirms it: only a test fixture has the key.
- The model comparison is in `state/reports/describe-comparison.md`. Every model described all 20 files in 4 units. Sonnet 5.5 cost $0.763 in 162 s and wrote 28.9K output tokens. Lint found 17 hits in its first drafts and 1 after the rewrites. Opus 5.5 cost $2.00 in 412 s and wrote 52.8K output tokens, with 5 lint hits in the first drafts and 0 after. GLM-5.3 cost $0 in 823 s and wrote 157.6K output tokens, most of them reasoning, with 7 lint hits in the first drafts and 1 after. Each model needed a rewrite on 3 units. The texts are comparably concrete and checkable. Opus describes more private symbols, and GLM adds `l3` caveats.
- Full first pass on Sonnet 5.5, estimated. At main there are 1,955 non-empty `.py` files under
  `lib/` (21.2M characters, 603 of them tests) in 227 directories. They form 251 units once
  directories over 280K characters are split. The estimate uses the measured rates: 2.4 characters per
  token, about 36K characters of README and neighbour context per unit, 1,450 output tokens per file
  and rewrites on 3 units in 4. That comes to about 24M input tokens (14M written to cache) and 2.8M
  output tokens, **about $65 for the files plus $4 for 16 subsystem pages, $69 in all**. With no
  rewrites the pass costs about $60. If every unit is rewritten at 2,100 output tokens per file it
  costs about $82. Without prompt caching it would cost about $81. The same model reproduces the
  comparison's measured Sonnet cost within 3% ($0.742 modelled against $0.763). On the same 3 units
  Opus 5.5 cost 2.56 times as much as Sonnet, which puts an Opus pass near $175.

Three failures turned up on 2026-11-01 and are fixed.
- API credit ran out after $8.69 of spend. The Agent SDK turn ended with `subtype: success`,
  `is_error: true` and the text `Credit balance is too low`, and Messages API calls returned
  `invalid_request_error` "Your credit balance is too low". The poller now prints one ERROR line and
  starts no more model work that tick. It queues the files and does not mark the PR head failed.
- GLM-5.3 and length limits. GLM-5.3 hit the 32K `max_tokens` cap because its reasoning spends
  the same budget. Requests now omit `max_tokens`, which follows the fleet log's audit. Without the
  cap, a 7-file unit ran past Node fetch's 300 s headers timeout (`fetch failed`), so completions now
  stream as server-sent events.
- Wrong timestamps. The model wrote local times marked `Z` in `prepared_at` and `updated`. The
  poller now sets both from its own clock.

## Departures from DESIGN.md

- Preparation does not build SCIP indexes for base and head. The agent finds symbols with `rg` and
  `git grep` in the PR worktree, and `prepare-pr.md` says `find_symbol` is unavailable.
- A preparation turn runs in a background session that the poller started. The app learns of the
  session only when it opens the PR and reads `session_id` from `pr.md`.
- `--describe-to` and `--dry-run` exist for backfills and tests. The design does not mention them.
