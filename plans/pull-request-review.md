# Pull request review

**Status (2026-10-04):** implemented by Fable, accepted backend repairs by
GPT Sol. Final gates **186 tests / 39 suites**, signed **20:18:12 CDT**, strict
codesign and packaged resources pass. Native attachment selected the old shared
reader twice; UI work stopped without actions or screenshots. Real diff probes
and one actual After Rust strategy generation/reuse/invalidation passed; Before
is syntax-only. See [Sol acceptance and manual checks](pull-request-ui-review.md).
Visual UI acceptance remains open; model/backend tests are separate evidence.

Radiology can read a GitHub pull request of the repository it is attached to:
pick one of the last 25 PRs from the toolbar, or press ⌘P and type a number.
Changed files, the callables that contain additions, and the added lines are
highlighted; every changed file has a per-file **Before / After** control. The
After revision is indexed like a repository, reusing every project index whose
bytes are provably identical to an index that already exists. This document
records the measured facts the design rests on, the identities and components,
the minimal UI, the implementation order, and the acceptance cases. Evidence of
the actual run is in `PROGRESS.md`.

## 1. Historical preflight facts (2026-10-04, read-only)

PR metadata changes over time. The table below predates merge/force pushes;
current pinned acceptance facts are recorded in plans/pull-request-ui-review.md.

Test repository: `/Users/tqbf/codebase/tk/tkos`, `origin = git@github.com:tktkinc/tkos.git`,
default branch `main`, checked out on `pr/phase-0-phone-compatibility` at
`239b9f6d`, `git 2.50.1`, `gh 2.94.0` logged in as `tqbf`.

| Fact | Value |
| --- | --- |
| Tracked files / bytes at HEAD | 10,094 files, 168.3 MiB of blobs; `.git` is 257 MB (8 packs) |
| `gh pr list --state all --limit 25` | 25 rows with `number,title,state,headRefOid,baseRefName,baseRefOid,isCrossRepository,mergeCommit,updatedAt` in ~1 s |
| PR #724 (open) | head `c9a5b050`, `baseRefOid` `488d8768`, 11 files: 2 added Kotlin (206 / 179 lines), `RuntimeSmoke.kt` +117 −205, `DesktopRuntimeSession.kt` 0 +55 −, plus TS/Python/Markdown/Gradle |
| PR #723 (merged) | head `f4082f9e`, `baseRefOid` `83682986`, merge commit `6af21769`, 12 files |
| PR #725 (open, large) | head `ec36ce1e`, base `8d1cfe94`, 514 files: 150 A, 160 M, 6 D, renames incl. `R100` and `R099` (`.patch`, Kotlin) |
| PR #691 | base branch is `pr/phase-0-phone-compatibility`, not `main` (109 files) |
| Merge base | `gh api repos/O/R/compare/{baseRefOid}...{headRefOid}` → `merge_base_commit.sha` (#724 → `488d8768`, #723 → `83682986`); GitHub's own "files changed" is this three-dot diff. `git merge-base` in a shallow clone returns nothing, so the API is authoritative |
| Fetch by SHA | `git fetch --no-tags --depth=1 origin <head> <base>` into an app-owned bare repository whose `objects/info/alternates` points at the user's `.git/objects` completed in 0.98 s (#724) and 1.1 s (#725). The user's repository is only read. GitHub serves PR head commits by SHA including fork heads (they live in the base repository's object network; `refs/pull/N/head` is the fallback) |
| Head checkout | `git worktree add --detach <dir> <sha>` from the bare repository: 1.5 s, 186 MB, 10,372 files, `.git` is a file pointing into the bare repo |
| Per-file diff | `git diff -U0 -M --no-color --no-ext-diff --no-textconv <base> <head> -- <path>` gives exact hunk headers; `--name-status -M -z` gives A/M/D/Rnnn with old and new paths |
| Existing tkos index | 13 `rust-analyzer` strategies, 220 s total (37.6 s largest), `index-metadata.json` format 2: HEAD, a path/size/mtime tree fingerprint, build-file contents. **No per-document byte provenance**, so nothing proves a format-2 strategy file matches a PR snapshot |
| Indexer granularity | rust-analyzer indexes a Cargo project (crate/workspace) whole; scip-go a module; scip-typescript/scip-python a project. None accepts a single-file subset. The smallest honest regeneration unit is one `IndexingStrategy` |
| Symbol ownership | `SemanticIndex` normalizes symbols, definitions, references and extents across every input when it is built. Removing a document from one strategy's SCIP file does not remove the symbols other documents reference, so "surgery" on a merged index is not a safe operation; replacement happens per strategy file, then the merged index is rebuilt |

## 2. Assessment of "clone the SCIP index and re-enter changed files"

The proposal works at the right granularity, and only there:

- **A strategy is reusable** for a snapshot when the entire repository blob context is byte-identical
  to the files the existing strategy file was generated from. Git blob IDs make
  this exact and cheap: `git ls-tree -r` yields them for a snapshot for free,
  and the working tree's are SHA-1 of `blob <len>\0<bytes>` (CryptoKit, ~0.5 s
  for 168 MiB) computed once per generation. The digest is recorded per
  strategy (`IndexMetadata.formatVersion = 3`, `StrategyRecord.contentDigest`).
- **A strategy is regenerated whole** when any of those files differ. This is
  what "chuck the entries for changed files and re-enter them" costs in
  reality for rust-analyzer, and it is what guarantees callers get regenerated after any unknown sibling/path/include
  dependency context changes. Dependency graphs are not inferred.
- **Cross-strategy references** (crate A reused, crate B regenerated, A refers
  to a B symbol by SCIP string) can dangle. Radiology does not model
  inter-project dependencies, so a mixed run is published as **Partial** with
  the reason spelled out, never Current. Persisted reusedFrom provenance preserves
  this Partial warning on reopening/refreshing even when outcomes are cached.
  All-generated or all-reused from a single provenance is Current absent other
  coverage problems. Different reused origins also remain Partial.
- **The format-2 working-tree cache is never reused** for a snapshot. Only
  format-3 records with a matching repository-context-v2 digest are candidates, whether they live in
  the working-tree cache (after the next reindex) or in another revision's
  cache. The new digest domain rejects the earlier project-local digests. Until dependency
  inputs are modeled, ANY repository byte change invalidates every strategy for
  cross-revision reuse; this is a correctness-first reduction in reuse. The earlier
  15/16 tkos project-local digest comparison is historical, not current reuse evidence.
  Identical whole-repository contexts still reuse strategy artifacts.
- Several indexes stay on disk, keyed by repository id, revision and strategy:
  `~/Library/Caches/Radiology/repositories/<repo-id>/revisions/<sha>/` holds
  `index-metadata.json` and one `.scip` per strategy; reuse copies files
  between these directories (never links into the user's repository).

What is deliberately not done: reading SCIP documents for changed files out of
an old index, or guessing occurrences from syntax. A file the After index does
not cover is reported "File not indexed", as today.

## 3. Identities

| Identity | Definition | Why |
| --- | --- | --- |
| Attached repository | The user's folder (`AppModel.attachedRepository`), the canonical root hash (`IndexCache.repositoryID`) | gh resolves the GitHub repository from it; Critical Lens marks and the working-tree index cache stay keyed by it in review mode; nothing in the user's folder is written |
| Review | `PullRequestReview { number, title, state, headSHA, baseSHA (merge base), baseRefName, headRefName, files: [FileChange] }` | Immutable once loaded. `headSHA` is the pinned head; a later force-push produces a different review (the list shows the new SHA; **Refresh PR / ⌘R** re-reads metadata) |
| Revision | `ReviewRevision = .before \| .after` on `SourceLocation`, `SourceBuffer`, `positions` keys, history entries | Before and After are different documents at the same path; caret, scroll, pins (via content identity), history and the semantic root must not cross |
| Snapshot roots | After: a `git worktree` of `headSHA` under `<repo-cache>/revisions/<sha>/tree/`; Before: `<repo-cache>/revisions/<base>/files/<path>` materialized on demand with `git show <base>:<path>` for changed files only | Unchanged files are byte-identical in both revisions and are shown from After with the control disabled ("Unchanged") |
| Review objects | `<repo-cache>/review.git`: bare, `objects/info/alternates` → user's `.git/objects`, `origin` = the attached repo's `origin` URL | Fetches by SHA, depth 1; missing alternate objects (user pruned) are refetched |
| Line changes | `FileLineChanges { hunks, addedLines (After), removedLines (Before) }` parsed from `-U0` output per file, cached per `(review, path)` | Drives gutter bars, line washes, changed-callable marks and Before/After line mapping |
| Index cache per revision | `IndexCache(root: <repo-cache>/revisions/<sha>/index, flat: true)` | Multiple indexes on disk keyed repo + revision + strategy; freshness by content digest |

## 4. Components

```
gh (read-only) ──► GitHubClient (protocol) ──► PullRequestSummary / PullRequestDetail / merge base
git (app-owned) ─► ReviewRepository (actor): fetch SHAs, ls-tree + blob ids, name-status, -U0 diff, show, worktree add/remove
                     │
                     ▼
            PullRequestModel (@Observable @MainActor): recent list, loading/error, active review,
            per-path revision choice, FileLineChanges cache, next/previous change
                     │
AppModel+PullRequests: openPullRequest(n) · exitPullRequest() · setRevision(_:for:) · toggleRevision()
                     │  swaps `repository` to the head snapshot, keeps `attachedRepository`,
                     │  normalizes SourceLocation.revision, routes SourceStore reads per revision
                     ▼
SemanticModel.repositoryOpened(headSnapshot, options) ──► SemanticIndexService.open(..., options)
     options: cache = revision cache, reuseSources = [working-tree cache, other revision caches],
              revision = headSHA, blobIDs from ls-tree
```

- **GitHubClient**: `gh repo view --json nameWithOwner`, `gh pr list -R … --state all --limit 25 --json …`,
  `gh pr view N -R … --json …`, `gh api repos/O/R/compare/A...B`. 30 s timeout per
  call; stderr becomes the error message ("gh: command not found", "not logged in",
  "no pull request found for 999"). `FakeGitHubClient` serves the tests.
- **ReviewRepository**: one actor per attached repository, all commands with
  cancellation and a timeout (fetch 300 s, worktree 180 s, others 60 s). It never
  runs anything inside the user's folder except `git rev-parse --git-path objects`
  and `git remote get-url origin`. Worktrees beyond the three most recently used
  are removed (`git worktree remove --force` + `prune`).
- **Per-file diff**: raw file records use full 40-character blob IDs. Hunks compare
  the exact before/after blobs (an app-owned empty blob for additions/deletions),
  avoiding unrelated patches when a rename's old path becomes a directory.
- **UnifiedDiff**: parses hunk headers `@@ -a[,b] +c[,d] @@`, ignores `\ No newline`,
  recognizes `Binary files … differ`, carries CRLF bytes untouched (git splits on
  `\n` exactly like `SourceBuffer`). Pure deletions have `+0,0`; pure additions `-0,0`.
- **LineMap**: maps a one-based line across revisions through the hunks: outside a
  hunk by cumulative delta, inside a hunk to the hunk's first line on the other
  side; used when toggling so the caret lands on the corresponding line.
- **Index reuse**: in `SemanticIndexService.run`, before launching a tool for a
  strategy, the digest is computed; each reuse source's metadata is scanned for a
  format-3 record with equal `strategy.id` and `contentDigest`; a hit copies that
  `.scip` into the revision cache and records `.reused(fromRevision:)`.
- **Freshness for snapshots**: equal per-strategy digests → Current without running
  anything; the mtime fingerprint is not consulted for snapshots.

## 5. Minimal UI (macOS idioms, no implementation words)

- **Toolbar** (navigation group, after Back/Forward): a `Menu` labelled with the
  active review (`#724`) or **Pull Request** with system image
  `arrow.triangle.pull`. Items: **Local Checkout** (checkmark when active),
  the last 25 PRs as `#724  Own desktop runtime startup…` with a trailing state
  (Open · Merged · Closed), **Open Pull Request… ⌘P**, **Refresh List**. The
  menu is disabled when the repository is not a GitHub repository or gh is
  unavailable, with the reason in its help text.
- **Exit PR** (2026-10-08 toolbar refinement): first action inside the labeled
  PR dropdown while reviewing or loading. Uses existing exit/cancel and
  returns to the attached local checkout without changing branches; pending open
  errors are cleared. Local Checkout is the selected row outside a review.
- **⌘P sheet "Open Pull Request"**: one number field, Cancel/Open, the same
  shape as Go to Line. ⌘K remains Go to File; the ⌘P alias is removed.
- **Review identity**: visible `#724` selector label; full title in Changes and
  PR menu/help. The duplicate window subtitle was removed in the toolbar refinement.
- **Sidebar**: review mode adds a **Changes** segment before Files/Search: a flat
  list using shared SourceFilters.includes (both Source Files Only and Hide Tests),
  preserving PR order and full canonical changes for indexing/diffs/navigation.
  Deleted paths use Before; renames/copies survive if either available path passes.
  Reused filter toggles appear in the header. File counts are visible-of-total;
  +/− totals are visible text-file changes, with binary-count caveat. Filtered-empty
  has No Changes to Show/Show All Files; genuinely empty has No Changed Files.
  Filtering/sync never navigates away from the current open file/caret/revision.
  System image per status (plus.circle, pencil.circle,
  minus.circle, arrow.triangle.swap, doc.zipper for binary), quiet `+n −m`
  tabular counts, old → new path for renames. Files mode is the full After tree
  with a small accent dot after changed entries.
- **Source header (breadcrumbs row)**: a trailing segmented **Before | After**
  control with a quiet status (Added · Deleted · Renamed from … · Unchanged ·
  Binary). Disabled segments explain themselves in help text. ⌥⌘B toggles.
- **Source**: added lines (After) carry a 3-point green bar in the gutter and a
  faint green wash; removed lines (Before) the same in red. Nothing changes
  layout or text. Compact native up/down buttons beside Before/After and existing
  ⌥⌘↓ / ⌥⌘↑ use shared per-direction availability. Inside a hunk, skip current;
  from an unchanged gap, choose nearest in direction; no wrap at ends. Navigation
  is guarded by current path/revision/content and loaded non-binary hunk data.
  Empty-side insertion/deletion points clamp to reachable EOF without adding
  changed-line highlights. EOF on an unterminated changed line is inside it;
  a trailing empty newline line is not. A genuine caret revision invalidates
  availability even for same-line moves; passive scrolling does not. Jumps record
  exact departure before existing navigate/reveal/highlight and return source focus.
  Long breadcrumb/status content scrolls horizontally within fixed header height,
  leaving Before/After and changed-block controls usable.
- **Outline**: callables containing a change get a small accent dot before the
  `n L` count. The Context inspector is otherwise unchanged.
- **Footer**: in Before, the semantic status reads **Not Indexed (Before)** and
  the Context inspector explains that Before is not indexed. The index popover
  shows reused strategies as "Reused from <sha> (identical bytes)".
- **Type**: no new type roles. Counts use `Theme.Fonts.meta` tabular digits like
  outline sizes; status words use callout secondary; the menu uses system menus.
  Diff colors are `systemGreen`/`systemRed` at 10 % light / 14 % dark washes and
  60 % gutter bars (see `Theme.DiffColors`).

## 6. Behavior contract

1. Opening a PR never blocks on indexing: metadata → fetch → worktree → file list
   → the Changes list appears; indexing starts afterwards and remains cancellable.
2. Before shows the merge base (`merge_base_commit`), After the pinned head SHA.
   Neither follows the user's checkout or a later base-branch tip. A changed head
   on GitHub is adopted through explicit Refresh PR / ⌘R; Refresh List stays separate.
3. Semantic navigation, references, previews and the call graph in review mode
   read the After worktree and the After index only. Before is syntax-only; no
   semantics are mapped onto Before bytes, so nothing stale can render.
4. Toggling records a history entry with the explicit revision; ⌘[ returns to
   the exact caret in the other revision. Positions, pins and folds are per
   revision (pins through content identity; folds reset like any file change).
5. Deleted files open in Before only; added files in After only; renamed files
   pair old and new paths; binary or unreadable files are listed but not opened.
6. Exiting a review (Local Checkout / Exit PR) reopens the attached folder; switching repositories cancels every review task and drops its
   state; a late result for an old review or repository is discarded.
7. PR open failures appear in a native alert even from Local Checkout, with
   Try Again (same failed number), Choose Number and Cancel. All gh/git failures
   preserve the current reader and
   leave the current view usable. No GitHub write, no `gh pr checkout`, no stash,
   no change under the user's folder.

### Initial changed-code visibility (2026-10-06)

Each newly loaded PR file/revision starts with its changed functions/blocks and
ancestors expanded once syntax and exact review/path/revision/content hunks are
matched. Signature, attached Rust attribute and Python decorator edits own only
their actual function body; untouched functions/sibling closures keep normal
fold defaults. Empty-side points can open a containing body (EOF included when
owned), not a closed unrelated neighbor, and never fabricate added/removed lines.
Manual fold toggles and bulk commands after opening, including diff-pending,
win. Fresh coordinators baseline old command counters. Defaults never navigate,
change bytes/caret/history, or silently unhide tests. Late layout preserves the
viewport row and cancels obsolete deferred navigation/position markers; a new
explicit jump supersedes pending viewport restoration. See structural-navigation.md
for parser/coordinator lifecycle and pull-request-ui-review.md for evidence.

### Active PR refresh (2026-10-06)

Refresh PR is a compact icon beside the labeled selector and appears in PR menus.
Exit PR lives inside that dropdown. One Cmd-R command
routes by context (active PR versus local repository reload), avoiding duplicate
key equivalents. Loading disables repeats, while old reader remains interactive.
Refresh List remains independent. Every refresh queries gh PR metadata plus a
fresh merge base, pins those exact SHAs, and uses existing bare/worktree pipeline.

Same head+merge-base only replaces summary/title/state and the existing recent
row: no document reset, history/fold/pin loss or reindex. Changed head OR base
prepares repository listing and source restoration BEFORE publishing review.
Active/candidate UUID worktree leases protect them from LRU eviction (oversubscribe
capacity while leased). Failure/cancel releases candidate but preserves old root.
Retry carries refresh intent; cancel/Exit/repository/other-PR discard late answers.

At commit, restoration uses latest current source/caret/viewport/pins, not a
click-time clone. If source is loading, await/reconcile the current task before
rechecking it; reader path/bytes moving during blob reads retries preparation.
Old→new revision Git rename records choose paths without spelling guesses. Exact
source equality preserves byte offsets; otherwise blob-to-blob Git hunks map lines,
retaining column only when mapped line bytes match. Available Before/After choice
is retained, or honestly switches with notice. Missing file falls to Changes.
Only current-file pins whose exact bytes match are retained/remapped; other pins
and SHA-obsolete navigation history/positions are dropped. Source mode, font,
filters, folder expansion and valid browser mode remain. Search results from old
root are cleared. Native word/range selection and manual folds are not cloned
across an actual snapshot change; new changed-fold defaults apply normally.

Atomic commit cancels old source/syntax/index/navigation/summary work and advances
generations, so old targets/hunks cannot leak. Before is still syntax-only; After
uses per-head cache with whole-repository context validation. Refreshed viewport
preserves source row through existing viewport restoration; next explicit
navigation supersedes it. No attached checkout/GitHub mutation, no polling.

Gates 234/47, signed 20:52:31 PDT, check/build/strict signing/env-i resources/diff.
FakeGitHub + temporary real Git regressions pass; no live UI or real remote-refresh
attempt. See pull-request-ui-review.md for manual checks/evidence boundaries.

## 7. Implementation sequence

1. `ReviewRevision`; `SourceLocation.revision`; `SourceBuffer.revision`; `positions` keys.
2. `PullRequest/UnifiedDiff.swift`, `FileChange.swift`, `LineMap.swift` + tests.
3. `PullRequest/GitHubClient.swift` (gh), `ReviewRepository.swift` (git) + tests on a local fixture origin.
4. Index: `RepositoryInspection.blobIDs`, content digests, `IndexCache.flat`, `IndexOpenOptions`, reuse step, `.reused` outcome + tests.
5. `PullRequestModel`, `AppModel+PullRequests`, launch argument `--pull-request N` + tests.
6. UI: toolbar menu, number sheet, subtitle, sidebar Changes/badges, breadcrumb control, gutter/wash, outline dots, commands.
7. Docs, gates, real tkos read-only exercise, signed build.

## 8. Acceptance cases

Model/backend (tests): hunk parsing for CRLF, Unicode, no-newline, pure add/delete,
rename with edits, binary; line map both directions; fetch-by-SHA + worktree +
materialize against a local origin; gh failure surfaces; stale-result discard
across review switches; digest reuse of an unchanged strategy and regeneration of
a changed one with a fake indexer; Partial status for a mixed run; history/positions
by revision; exit restores the attached repository.

Real data (read-only, recorded in PROGRESS): #724 (added/modified/removed-only
Kotlin, Python, TS), #723 (merged), #725 (514 files, renames), #691 (non-main base).

UI (GPT Sol, signed build): menu/sheet flows, Changes list, Before/After per file,
line/function/file highlighting, Back after toggle, Local Checkout, errors.

## Acceptance repairs (GPT Sol)

Mixed cache provenance survives reload/refresh; refresh retains revision cache
options. Digests conservatively include all repository blobs, versioned to reject
prior project-only provenance. PR failures are globally visible with retry/number
recovery; Choose a File correctly says Cmd-K. File hunks compare full pinned blobs
rather than pathspec unions, including rename-old-path directory reuse.
See plans/pull-request-ui-review.md for final gates, native blocker, real adapter
smoke and manual screenshots. These backend gates do not establish UI acceptance.

## Shared sidebar filtering correction — 2026-10-05

User reported Markdown in Changes with Source Files Only enabled. Changes now
uses the same SourceFilters.includes policy as Files for BOTH filters, including
rename/copy either-available-path semantics and deleted Before paths. Visible
counts/totals and filtered-empty/reset are explicit; canonical review data and
open reader/history/revision stay untouched. Gates 216/44 signed 19:00:13 PDT;
no native retry. See source-filters-ui-review.md for manual checks and evidence.

## Changed-block source affordance — 2026-10-06

Gates 220/45, signed 14:22:51 PDT, check/build/strict signing/env-i resources and
clean diff check. ChangeBlockNavigation tests hunk boundaries, gaps, EOF and
empty sides; AppModel integration tests exact Back after passive scroll, hidden
test reveal, observation invalidation and stale/binary/pending guards. Native
attachment selected old shared #753 reader twice; no actions or screenshots.
See pull-request-ui-review.md for explicit manual checks/limits.
