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
   - The other changes, plus any deferred queue, are grouped by directory into units, and each unit's
     slices that hold a changed source file run (`Poller.planJobs`). A changed test file rides with
     its owner unit's slice, or goes to an orphan batch when that slice is not running. Each prompt is
     one model call (`describe.ts`) with one rewrite when the reply fails the schema or the lint.
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

`units.ts` `ContextBuilder` assembles one prompt per unit from `prompts/describe-unit.md` (rules of
2026-11-02). Nothing is cut: every file in a prompt is its full source, and the whole prompt
(template, style guide and every block) stays within `PROMPT_BUDGET`, 256K tokens. Tokens are counted
with js-tiktoken 1.0.21's `o200k_base` (`tokens.ts`). OpenRouter does not publish GPT-6.1 Terra's
tokenizer, but Terra billed o200k plus 6 tokens of framing on all 8 prompts measured.

A unit is one directory of source files under `lib/`. Test files are not units:

- **Owner.** Each test under `lib/` belongs to the source directory it imports the most names from
  (`assignOwners`; a tie goes to the test's own package). The owner carries the test in full in every
  prompt and writes its one-sentence `l1` in the reply's `tests` map. Test entries have `l1` and
  `test: true` only (`buildTestEntry`).
- **Orphans.** Tests that import no described code (`conftest.py`, helpers that import only other
  tests or third-party code) go into orphan batches by directory, as many per batch as fit, with no
  neighbours (`packOrphans`, `orphanBatches`).
- **Poller.** A changed test rides with its owner when the owner's slice regenerates in the same tick;
  otherwise it goes to an orphan batch.

The budget fills in this order: the unit's own files, the README, the unit's own tests, the subsystem
page, existing entries and diff (these are reserved first, so they always fit), then the other tests
that import the unit, then neighbours. Neighbours are modules the unit imports or that import it,
anywhere in the checkout but `vendor/` (upstream evalchemy, harbor and skyrl, which Marin's own linters
exclude) and ignored paths. They are offered by `diversityOrder`: non-test code first, round-robin over
packages (`experiments`, `scripts`, `tests` and `infra` count as packages), the unit's own package
first. `fillBudget` skips one that does not fit and tries the next, and the exact count of the
assembled prompt has the last word. What is left out is listed in a `LEFT OUT` block and in the log
line (`describeStats`).

A directory whose own files plus own tests pass the room after the fixed blocks is split by
`planSlices` into slices of about equal size, each filled to at most 80% of that room, so neighbours
keep some space. Each test rides with the file it imports the most names from. The other slices'
files are offered as neighbours. An owned test that cannot fit beside its file goes to an orphan
batch (`PlannedUnit.overflow`).

The import graph is one `git grep` per commit over every covered `.py`. `ModuleIndex` maps modules
with the src layout under `lib/` and from the repository root elsewhere (`experiments.grug.base`). A
module name two packages share (`tests.conftest`) resolves to the importer's own package.
`resolveNames` counts imported names per edge, which the owner rule uses. Multi-line imports count as
one name, because the grep sees only the first line.

The blocks are `SOURCE`, `README`, `TEST`, `NEIGHBOUR`, `SUBSYSTEM`, `EXISTING`, `DIFF` (uncut),
`LEFT OUT`, `TARGETS` and `TEST TARGETS`. The model may answer `{"keep": true}` only for a target that
already has an entry.

`npm run compare -- --estimate` plans and builds every prompt of a first pass at the comparison's
commit without calling a model (`pass.ts`), under the current rules and under the earlier rules in
which test directories were units and a source unit carried every test that imports it. The results
go into the comparison JSON and the report.

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

## GPT-6.1 Terra on OpenRouter

`pipeline/openrouter.ts` `OpenRouterBackend` runs the same `describe-unit.md` prompt and unit builder
through OpenRouter's OpenAI-compatible `/chat/completions`. It streams the reply and sends
`service_tier` and `reasoning: { effort }`. It retries a 429 or 5xx up to 3 times. From each reply it
records the cost, the tier that served it, the reasoning tokens, the upstream provider and the
generation id. The cost comes from `usage.cost`, then from `GET /generation?id=` when that is
missing. A reply with no cost is an error and is never recorded as free.

- **Key.** `openRouterKey` in `config.ts` reads `OPENROUTER_API_KEY` from the viewer's `.env`, then
  `OR_KEY_SCALE_UP` from the parent directory's `.env`. `MARIN_VIEWER_OPENROUTER_ENV_FILE` and
  `MARIN_VIEWER_OPENROUTER_KEY_NAME` replace the first source. Only the file and variable name are
  ever printed. Run from a worktree, set `MARIN_VIEWER_ROOT` to the marin-viewer directory, or the
  fallback looks in the worktree's parent.
- **Model.** The model is `openai/gpt-6.1-terra` (canonical `openai/gpt-6.1-terra-20261026`) from the
  public `GET /api/v1/models`, with 1.05M tokens of context and up to 128K output. The listed prices
  per million tokens are $1 input, $5 output, $0.05 cache read and $1.25 cache write. Above 272K
  prompt tokens they rise to $2, $7.50, $0.10 and $2.50. A `:batch` variant costs half.
- **Service tiers.** OpenRouter takes a top-level `service_tier` (`default`, `flex`, `priority`, with
  `fast` as an alias, plus `ultrafast`). Each tier is its own endpoint with its own price, listed by
  `GET /api/v1/models/openai/gpt-6.1-terra/endpoints`:

  | Tier | Endpoint tag | Input / output | Cache read / write | Multiple of default |
  | --- | --- | --- | --- | --- |
  | flex | `openai/flex` | $0.50 / $2.50 | $0.025 / $0.625 | 0.5 |
  | default | `openai` | $1 / $5 | $0.05 / $1.25 | 1 |
  | priority | `openai/fast` | $2 / $10 | $0.10 / $2.50 | 2 |

  An Azure EU endpoint is listed at $1.20 / $6. The response's top-level `service_tier`, and the
  generation record's `service_tier` and `provider_responses[].routed_service_tier`, report the tier
  that served the request. Billing follows the served tier, so a priority request that falls back to
  a standard endpoint pays the standard rate (OpenRouter's Service Tiers guide). Model and endpoint
  `supported_parameters` do not list `service_tier`, yet requests take it.
- **Billing.** Every uncached prompt token was billed at the cache-write price. For the shellbox local
  unit, `usage.cost` and the generation record's `total_cost` were both $0.114006, which is exactly
  31,203 prompt tokens at $2.50 plus 3,600 output tokens at $10. The record's negative
  `cache_discount` (-$0.0156) is the write surcharge.
- **Reasoning effort.** Neither the reply nor the generation record says which effort was applied. A probe
  sent one prompt at each setting: low gave 169 reasoning tokens, medium 287 and high 338, and the
  call with no setting gave 285. So the effort is honoured, and medium matches the model's default.
  That is one call per setting. On description units Terra reasoned for only 54 to 96 tokens a call.

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
- The model comparison is in `state/reports/describe-comparison.md`. Every model described all 20 files in 4 units. Sonnet 5.5 cost $0.763 in 162 s and wrote 28.9K output tokens. Lint found 17 hits in its first drafts and 1 after the rewrites. Opus 5.5 cost $2.00 in 412 s and wrote 52.8K output tokens, with 5 lint hits in the first drafts and 0 after. GLM-5.3 cost $0 in 823 s and wrote 157.6K output tokens, most of them reasoning, with 7 lint hits in the first drafts and 1 after. Each of those three needed a rewrite on 3 units. GPT-6.1 Terra (effort medium, priority requested and served) cost $0.372 in 80 s by OpenRouter's `usage.cost`. It wrote 12.4K output tokens and passed lint on every first draft, so it needed no rewrites. The first three write comparably concrete and checkable text. Opus describes more private symbols, and GLM adds `l3` caveats. Terra writes about half as much: its `l1` lines average 87 characters to Sonnet's 138 and its `l2` 344 to Sonnet's 657, though it lists the most symbols, 9.1 per file. Its text is accurate on the files read, but it leaves out details that Sonnet gives, such as the compression and the error mapping in `iris/actor/client.py`.
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
- Every model, from the same token model. `pipeline/estimate.ts` now computes the estimates in the
  report's Estimates section. Each model's output per file, rewrite share and input tokens against
  Sonnet are measured on the 4 comparison units, and the 16 subsystem pages (about $4) are left out.
  The file passes come to:

  | Pass | Estimate |
  | --- | --- |
  | Sonnet 5.5 | $65 |
  | Sonnet 5.5, Batch API | $32 |
  | Opus 5.5 | $176 |
  | GPT-6.1 Terra, priority | $32 |
  | GPT-6.1 Terra, default | $16 |
  | GPT-6.1 Terra, flex | $8 |

  The Terra figures rest on 0.57 times Sonnet's input tokens, 620 output tokens per file and no
  rewrites. Its tokenizer appears to need fewer tokens for this Python. Sonnet's first-call input
  here is taken as half of a rewritten unit's input, which slightly understates that ratio. On the 4
  units themselves, Terra's flex tier would have cost $0.093 against $0.372 at priority. Repricing
  the recorded tokens at priority prices gives back exactly the $0.372 that OpenRouter charged.

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

## The first pass

`npm run first-pass` (`first-pass.ts`, with the scheduling in `pipeline/firstpass.ts`) describes every
source unit and slice at the clone's current `main`, then the orphan test batch. It writes no subsystem
pages; `npm run system-pages` does (below).

- **Model.** GPT-6.1 Terra at effort medium, `service_tier: "flex"`, pinned with
  `provider: { only: ["openai/flex"], allow_fallbacks: false }`. OpenRouter's Service Tiers guide says
  a flex request falls back only to endpoints priced at or below flex, and the pin rules even that
  out. A probe on 2026-11-02 was served `flex`, and its generation record's
  `routed_service_tier` was `flex`.
- **Tier guard.** As a second line of defence, any call served on another tier stops new units.
  The run prints `ERROR tier`, lets the units in flight finish, and exits with status `tier`.
- **Window.** A sliding window of calls in flight starts at 128 (Mark, 2026-11-02). After a full
  window of clean calls whose median latency is within twice the first round's, it grows by half, up
  to 256. A capacity error (429, 5xx, a flex capacity error or a dropped stream) halves it and is
  retried with backoff of 5 s doubling, capped at 120 s, up to 8 attempts. A 402 stops the run.
  Eight failed units in a row with no success between them stop it too.
  - Every attempt takes a slot, retries included, so a halved window really holds the calls in flight
    to the new size. A capacity error also pauses new calls for its backoff.
  - Errors from one burst count once. A call carries the epoch it started in, and only an error from
    the current epoch halves the window. The first live run (14:05Z) lacked both: 128 calls hit
    `502 Flex processing is temporarily unavailable` together, halved the window to 4 within a second,
    and still retried all 128 every few seconds.
- **Spend cap.** No unit starts once reported spend (`usage.cost`) reaches `--cap`, $35 by default.
  Every 10 units, a progress line compares spend against the estimate for the units done.
- **Validation.** One rewrite turn per unit, then `salvage`. The entries the reply holds for real
  targets are written, each carrying its validation problem in `lint:`. Files the reply left out stay
  missing and are named by the completion check.
- **Protected entries.** An entry whose `by:` does not name a model run (`isGenerated`) is never
  overwritten. The 16 hand-written shellbox entries of the #10640 fixture stay as context.
- **Resume.** A unit is done when every file it owns has an entry at the pass's commit. The state file
  `state/runs/first-pass-<sha7>.json` records each unit's status. A unit recorded as done that no
  longer reads as done stops the run before it starts, and so does a wordbase that lists nothing.
- **Lock.** `state/first-pass.lock` holds the pid. The poller does nothing while that process lives.
- **Output.** Each unit adds one log line to `state/runs/first-pass-<sha7>.log`. A `GAP` line appears
  after 5 minutes with no unit finishing. The wordbase is committed every 20 units, after
  `check_fixture.py --entry` over the batch. Failures of `system X has no entry` are only counted,
  since this pass writes no subsystem pages. Every other failure is printed as an `ERROR` line.
- **Completion check.** At the end, and with `--check`, the run counts source and test files with
  entries at the commit against the files expected, and names each missing file with its unit's
  reason.

## Measured on 2026-11-02: the first pass at 1d274b5

- **Result.** 184 of 184 units done and 0 failed, in 28.0 min (14:09:29Z to 14:37:32Z). The completion
  check counts 1331 source entries written plus the 16 hand-written ones, of 1347 expected, and 608 of
  608 test entries. Nothing is missing, and no entry carries `lint:`. 50 units took the rewrite turn.
  None kept a validation problem.
- **Spend.** $5.68 reported, all served on flex, against the $17.00 estimate. The early, smaller
  units ran at about 15% of their estimate, and the whole pass at 33%. The OpenRouter key's
  `usage_daily` matched the ledger to the cent ($7.379 for the day), so `usage.cost` is the real charge.
- **Flex capacity.** The flex endpoint is the bottleneck, and the window cannot raise it. 148 calls got
  `502 Flex processing is temporarily unavailable` and were retried. The window spent the run between
  4 and 9, and 12 was the most it reached after the opening collapse. Successful calls averaged 4.8
  in flight. Call latency was 27 s at the median, 64 s at p90 and 122 s at most. 234 calls served
  184 units. A unit took 158 s at the median, retries included.
- **Wordbase.** Ten commits, `f7f40aa` to `d5b7e76`. The shellbox fixture's 16 hand-written entries
  are unchanged. `check_fixture.py` over the whole wordbase still gives the 2 WARN and 2 MISMATCH
  lines of the baseline. It adds 1386 failures of `system X has no entry`, one for each entry whose
  system has no page yet, since this pass writes none.

## Subsystem pages

`npm run system-pages` (`system-pages.ts`, with the page logic in `pipeline/systems.ts`) writes one
page per package under `lib/` at the clone's `main`, in the DESIGN.md section 6 system format, with
the map the strip's "In Marin" card draws. The poller's subsystem refresh (`refreshSystem`) uses the
same writer.

- **Models.** Fable 5.1 (`claude-fable-5-1`, effort high) writes the page. Opus 5.5 reads it cold
  (`prompts/cold-reader.md`), before and after one rewrite. Both run on the Claude key.
- **Order.** Packages go in dependency waves (`dependencyWaves`), so a page's neighbours already have
  their `l1` when it is written. A neighbour without a page shows its README's opening paragraph.
- **Kept pages.** A page whose `by:` names no model run (`isGenerated`) is kept. At 1d274b5 that is
  `systems/shellbox.md` (`by: claude-opus-5-5 fixture ...`), the #10640 fixture's page.
- **Context.** `systemInputs` fills a 256K o200k budget in this order, and the log names what it left
  out:
  1. the neighbours' `l1` lines (reserved first);
  2. every source file's `l1`, then `l2` paragraphs while they fit;
  3. the tests' `l1` lines;
  4. the README, cut if needed;
  5. entry-point excerpts, within `--excerpt-budget`: the top-level `__init__.py`, the
     `pyproject.toml` script modules, `__main__`/`cli`/`main` modules, then modules by outside
     importers. A file over 12,000 tokens is given as its definition lines.
- **Reply.** The writer replies under a JSON schema (`PAGE_SCHEMA`, structured outputs), with
  `l1`, `l2` and `diagram` required. Edges come back as `{from, to, label}` objects, and
  `normaliseDiagram` turns them into the wordbase's `[from, to, label]` arrays. Without the schema,
  Fable left the map out on the first dupekit trial, and on another wrote edges as objects that the
  map schema rejected.
- **Checks.** `checkPage` holds the map to the card:
  - at most 10 boxes, 4 columns by 3 rows, one box per cell;
  - a box named for the package and one for each neighbour, each with its `lib/<name>/` path; a
    merged box lists its packages under `systems`;
  - paths that exist at the commit;
  - labels of up to 3 words and subs of up to 5;
  - edges between real boxes.

  Map problems, lint hits and cold-reader gaps all go back in the one rewrite. A map that still fails
  is dropped, and its problems are recorded in `lint:`.
- **Keeping the better version.** When the cold reader finds more gaps in the rewrite than in the
  first draft, and the draft had no lint hits or problems, the draft is saved. The state file records
  both counts and `kept: draft` or `kept: rewrite`.
- **Whole excerpts.** `--excerpt-full-max <tokens>` raises the 12,000-token limit above which a file
  is given as its definition lines.
- **Caching.** The rewrite reads the writer's prompt from cache. The cold reader's prompt puts CODE
  before DESCRIPTION, and the code half is sent as its own cached block (`cachePrefix`), so the second
  read takes it from cache.
- **Spend cap.** `--cap`, $25 by default, counts every call of the run at this commit from the
  ledger, earlier invocations included. A call that would start past the cap raises `SpendStop`.
- **Resume.** A page is done when its `by` is `claude-fable-5-1 system-pages <sha7>` at the commit.
  `--redo a,b` writes those pages again. The state file is `state/runs/system-pages-<sha7>.json`, and
  every call's reply text is kept under `state/runs/system-pages-<sha7>/<page>.json`.
- **Lock.** `state/system-pages.lock`. The poller does nothing while that process lives.
- **Output.** After each wave, `check_fixture.py` checks the wave's pages, and the wordbase is
  committed with each page's gaps and cost in the body.

## Measured on 2026-11-02: subsystem pages at 1d274b5

- **Result.** 15 pages written, 0 failed; shellbox kept. Every page has a map that passes
  `checkPage`, and no page carries `lint:`. `check_fixture.py` over the whole wordbase gives the 2 WARN
  and 2 MISMATCH lines of the baseline and no `system X has no entry`.
- **Spend.** $23.18 of the $25 cap: Fable 5.1 $17.92 and Opus 5.5 $5.26. The 15 final pages cost
  $21.21. Five dupekit trials while the map and cache fixes went in cost $1.96.
- **Excerpt budget.** The first 7 pages (dupekit, haliax, rigging, verifyit, finelog, finestore,
  iris) ran with `--excerpt-budget 20000`. They cost 1.25 to 1.4 times the estimate, which put the
  whole run on course for about $27, so the run was stopped between waves. The other 8 ran with
  5,000. iris's prompt was the largest, at 63K o200k tokens (110K counted by Claude). No page came
  near the 256K budget, so only excerpts were left out: from 0 entry points (dupekit, ducky) to 215
  (marin). rigging, finelog, fray and marin have no README.
- **Prompt wording.** After the run, one line of `describe-system.md` was reworded to pass the prompt
  lint ("several of them:" read as a counting opener). The pages were written with the old line.
- **Tokenizer.** Claude's count ran about 1.7 times o200k on these prompts. Opus 5.5 counted the
  same text at about 0.71 of Fable 5.1's count.
- **Cold reader.** 52 gaps before the rewrites and 19 after. The rewrite cut gaps on 11 pages. fray
  had none and took no rewrite. finelog and rolloutengine stayed at 1. haliax went from 2 to 5: the
  rewrite added claims its inputs do not show. The haliax redo below replaced that page.
- **Time.** 20.4 min of wall clock for the 15 pages, up to 4 pages in flight. A page took 35 to 204 s.
- **haliax redo** (Mark, 2026-11-02). Run with `--redo haliax --excerpt-budget 150000
  --excerpt-full-max 150000`, so all 20 entry points went in whole, none as definition lines and none
  left out. Before, 6 went in and 14 were left out. The prompt was 99K o200k tokens (162K counted by
  Claude). The cold reader found 3 gaps in the draft and 3 in the rewrite, so the rewrite was kept.
  It cost $3.57: Fable 5.1 $2.63, Opus 5.5 $0.94. Both cold reads after the first took the code from
  cache. Wordbase commit `9a9bdd9`. The run's total is now $26.76.

## Measured on 2026-11-02: full context

- **Comparison.** GPT-6.1 Terra (effort medium, priority) on the same 4 units with the full context:
  $1.317, 88 s, no lint hits, no rewrites, 637 output tokens per file. Prompts:
  - `local`: 82.7K tokens;
  - `daytona`: 56.0K;
  - `actor`: 86.6K;
  - `finelog/client`: 250.7K, with 50 neighbours shown and 5 left out.

  The old prompts were 19.7K to 31.2K tokens.
- **Tokenizer.** Terra's billed `prompt_tokens` was o200k plus 6 on all 8 prompts, old and new.
- **Full first pass at 1d274b5** (`--estimate`), current rules:
  - 183 source prompts and 1 orphan batch of 33 tests;
  - 23.6M input tokens;
  - Terra $17 on flex, $34 on default, $68 on priority, with test `l1` output assumed at 80 tokens.
- **The same pass under the earlier rules** (test directories as units, every importing test
  mandatory): 253 prompts, 34.0M tokens, $24, $49 and $98. Of its 16 splits, 14 are source directories
  that carry tests as heavily imported as `rigging`'s, and 2 are test directories.
- **Splits under the current rules.** One: `lib/iris/src/iris/cluster/controller`, 41 files into slices
  of 33 and 8 files carrying 17 and 8 owned tests.
- **Ceilings.** No prompt passes 272K. Under the current rules, 58 of 184 prompts fill past 240K and
  57 leave neighbours out. Those 58 hold 63% of the pass's tokens, so the neighbour fill drives the
  cost. The median prompt is 92K.

## Departures from DESIGN.md

- Preparation does not build SCIP indexes for base and head. The agent finds symbols with `rg` and
  `git grep` in the PR worktree, and `prepare-pr.md` says `find_symbol` is unavailable.
- A preparation turn runs in a background session that the poller started. The app learns of the
  session only when it opens the PR and reads `session_id` from `pr.md`.
- `--describe-to` and `--dry-run` exist for backfills and tests. The design does not mention them.
