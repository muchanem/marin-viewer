# Pull request UI and functional review

## 2026-10-04 — GPT Sol acceptance and repairs

Final signed binary: **2026-10-04 20:07:43 CDT**, build/Radiology.app.
Actual gates: make check; **186 tests / 39 suites**; make build (swiftbuild);
strict deep codesign; env-i packaged resources from /tmp, eight grammars/all
calls queries. Full final suite passed. One earlier full run exposed an existing
semantic navigation test racing document-semantic loading after Back; the test
now waits for the correct document before asking for an external definition.

### Native evidence boundary

Launched a separate fresh signed review app with tkos/app_image.rs, preserving
the older user process. Bundle-ID attachment selected the user's app.rs:3026
reader (one pinned group, four occurrences), not the fresh instance. The single
full-path recovery returned the same window. Stopped within the bounded setup
budget without clicking, typing, navigating, or altering marks/pins. Closed only
review PID 78172; original PID 87944 remained. No screenshots were taken, and
NO new PR UI, menu/sheet, pointer navigation, colors, dark mode, responsiveness
or index cancellation behavior has been verified live. Final repaired build was
not relaunched: the native budget was already spent. This round does not turn
previous hover physical-click or ordinary outline visual limits into passes.

### Concrete fixes and regression evidence

- Mixed reused/generated provenance is recovered from persisted reusedFrom
  records when outcomes are cached; reopening and refresh remain Partial.
  Different reused origins also remain Partial. Refresh retains revision cache
  options instead of silently switching to the working-tree cache.
- Native root-level PR failure alert works from any sidebar mode by construction:
  Try Again retries the failed number, Choose Number reopens lookup, Cancel
  dismisses. Current reader is preserved. Model failure/retry coverage passes;
  actual alert presentation/keyboard flow remains manual.
- Choose a File and quick-file-picker documentation correctly use Cmd-K.
- Per-file hunks compare exact full 40-character before/after blob IDs, using an
  app-owned empty blob for add/delete. Regression reproduces R100 uni.rs→new.rs
  plus added uni.rs/added.rs: unchanged renamed file has no hunks; the unrelated
  added child has only its own hunk. Line-map identity and add/delete coverage pass.
- Digests include ALL repository blobs until dependency inputs are modeled.
  Versioned repository-context-v2 rejects former project-local digests. Sibling
  source/include changes invalidate reuse and regenerate, with regression coverage.
  This deliberately reduces cross-revision reuse; no dependency inference added.

### Actual read-only GitHub/backend evidence

At final probe: tktkinc/tkos, 25 recent PRs, newest #736 (11 open, 13 merged,
1 closed). These are time-specific observations, not stable future expectations.

| PR | State | Exact head | Exact merge base | Real diff |
| --- | --- | --- | --- | --- |
| 724 | Merged | f11c99e3d66171cf7eda5167d80a94afa2d6747f | 488d8768d55a4e88a772c673bada7d89168aed0f | 9 files: 7 M, 2 A |
| 723 | Merged | f4082f9e3ab0f5b363ff5300acd7bf8ccf78a19e | 8368298660b3a5a15398a88767775a610779b90f | 12 files: 5 M, 5 A, 2 D |
| 725 | Open | 3dd325f6b065526a661b58b835ba5ab656c56a4b | e7380c8269f06b69ea89d08da81925687e66f3b0 | 744 files: 390 M, 336 A, 11 D, 7 R |

Real fetch, diff, Before materialization and exact-head worktree probes passed.
#724 DesktopRuntimeSession.kt is 238→183 lines: removed Before ranges
[3..<5, 11..<64], no added After lines, After anchors [3,9]. RuntimeSmoke.kt
has 17 hunks +117 −205. The final conservative policy finds **0/16** matching
head/base strategy digests; previous 15/16 project-local comparison is superseded.
#725 SegmentedJournal.kt is a renamed-and-modified source→test file.

**Actual snapshot Rust adapter smoke**, temporary cache, only
`tools/phone-provisioner` at #724 exact head, rust-analyzer 1.97.1
(8bab26f4 2026-07-14): generated one SCIP document in **7.48 s**, Current,
validated **3,711** occurrences against exact After source bytes (zero unmapped).
Same-context cache copied/reused that real artifact in **0.063 s**, Current.
Simulated sibling-context digest change rejected reuse and regenerated the real
project in **2.47 s**, Current. The simulated digest is a provenance invalidation
exercise, NOT an actual edited second revision; neither tkos nor snapshot source
was rewritten. All three runs use the existing adapter/config and service/SCIP
normalization. No dependency installation, vendoring or manifest repair. This
proves one quick strategy, not a complete 16-project snapshot, every dependency,
index quality, GUI cancellation, or GUI latency. Before remains syntax-only.

Final opt-in command (both tests passed):

```sh
RADIOLOGY_REAL_PR_PROBE=1 RADIOLOGY_REAL_PR_INDEX_PROBE=1 swift test --filter PullRequestRealDataProbe
```

Backend logs: /tmp/radiology-pr-review/backend/ (final-real.log, check.log,
test.log, build.log). These are logs, not screenshots. TkOS HEAD and porcelain
status matched before/after; user process and marks/pins were not interacted with.
No commits/pushes, GitHub writes, or tkos writes; RADIO.png pipeline preserved.

### Precise manual UI checks and screenshot requests

Use the fresh signed app when the user is ready; do not substitute the older
running reader. Query current PR SHAs first if metadata moved since this report.

1. Capture expanded Pull Request menu: 25 recent entries with number/title/state,
   Local Checkout and lookup. Cmd-P must focus number; Esc preserves reader;
   Cmd-K still opens file lookup. Enter an unknown PR number: capture the native
   error alert and verify Try Again/Choose Number/Cancel with reader unchanged.
2. Open #724. Capture Changes list/subtitle (9 files, status/counts), then
   `tools/tk-desktop/src/main/kotlin/inc/tk/os/engine/DesktopRuntimeSession.kt`.
   Capture After at line 9 and Before lines 11–64: After has no green added lines;
   Before shows removed red lines and Not Indexed (Before). Kotlin remains
   syntax-only rather than implying Rust coverage.
3. Place a precise caret, scroll away, Alt-Cmd-B then Cmd-[. Verify exact original
   revision/file/caret. Alt-Cmd-Up/Down in After visits anchors 3/9. RuntimeSmoke.kt
   captures should show correct hunk marks and changed-callable outline dots.
4. #724 DesktopRuntimeProcess.kt: capture Added with Before unavailable. #723
   scripts/prepare-pty-helper.py or scripts/prepare-vm-payload.py: capture Deleted
   Before with After unavailable. #725 journal/src/test/kotlin/inc/tk/os/journal/
   SegmentedJournal.kt: capture old→new path/status, both revision bytes, mapped
   toggle and exact Back. Unchanged files must not invent a different Before;
   binary availability is fixture-tested only (these real PRs contain no binary).
5. On an indexed After Rust call, test definition/reference click or Return and
   exact revision-aware Back. Before must offer no stale After semantic target.
   Inspect index reuse provenance/Partial after refresh; Cancel indexing should
   leave browsing responsive. Full snapshot generation/cancellation is manual.
6. Cmd1/Cmd2 must preserve source state and concise sidebar, outline ordering and
   counts; diff shade/caret/pins should remain readable. Capture at normal and
   narrow width (dark only if straightforward). Choose Local Checkout, confirm
   review state clears and attached checkout returns without repository mutation.

Design verdict: source-level native controls and existing type roles are coherent;
backend correctness repairs are gated. **Visual/functional UI acceptance remains
open** because the tool could not attach to the fresh reader. No visual defects
were fabricated or claimed fixed from model evidence.

## 2026-10-04 20:18 — Visible exit affordance

Signed binary 20:18:12 CDT. Check, 186 tests/39 suites, swiftbuild build, strict
deep codesign and env-i eight-grammar/all-calls verification pass. Exit PR is a
native Button with explicit titleAndIcon and return arrow, directly beside the
PR selector while active/loading. It uses existing exitPullRequest: cancel load
or return to the attached local checkout, clearing pending load errors/failed
number. It does not switch branches or label the destination main. Menu Local
Checkout remains. Existing error/retry regression now verifies cancel suppresses
late errors and preserves local reader/history. No button-wiring mirror test.

No native attempt, screenshots or new live claims: user explicitly requested no
further attachment workaround for this affordance. Manual check: open or start
loading a PR, confirm Exit PR text beside selector, click it, verify local
checkout browsing returns with no stale failure alert or branch change. User
reader/pins/marks were untouched; preceding UI/hover/outline limitations remain.

## 2026-10-06 — Changed-block source-header navigation

Final signed binary **14:22:51 PDT**. Actual gates: 220 tests/45 suites,
make check/build swiftbuild, strict deep codesign, env-i eight-grammar/all-calls
resources, clean diff check. Native component/model evidence is NOT live UI.

Two compact native borderless up/down buttons beside Before/After, 24-point hit
frames, accessible Previous/Next Changed Block names and shortcut tooltips, share
model availability with existing ⌥⌘↑/↓ menu actions. No quiet count was necessary.
Breadcrumbs/status horizontally scroll at fixed header height; controls remain
fixed-size. Each hunk is a block in current revision: inside skip to adjacent;
in gap choose nearest direction; no wrap. Empty sides remain point destinations,
EOF included without fabricated line highlights. Unterminated final changed-line
EOF caret is inside that block; trailing empty newline line stays outside.
Path/revision/content guards and pending/binary/unchanged state disable actions.
Availability observes actual caret changes, including same-line movements, rather
than passive scroll positions. Jumps use existing navigate/reveal/highlight,
record exact caret departure first, and focus source. Tests cover stale data,
EOF, directions, Observation invalidation, Before/After, passive-scroll Back and
hidden-test reveal. Existing fold/pin/copy/source-mode suites pass.

Attempted fresh signed snapshot_policy.rs instance. Bundle-ID and one full-path
recovery attached to user's old #753 app.rs PR reader. Stopped within budget,
no clicks/keys/screenshots, closed only review PID 49593; user PID 33005 remains.
No UI verification/visual verdict is claimed. No tkos/pins/marks/branch/GitHub
writes. Earlier PR/hover/outline/filter gaps do not become passes in this round.

Manual check/screenshots: on fresh signed build open PR #724's RuntimeSmoke.kt
(recorded head f11c99e3d6 has 17 hunks; verify current SHA if changed). Capture source
header at normal/narrow width: Before/After and up/down controls remain usable
with long paths. From inside a changed hunk use buttons and ⌥⌘↑/↓; both skip that
hunk, from a gap choose nearest, and disable correct direction at ends. Capture
first/last states and a gap. Place exact caret, passively scroll, click Next, then
Cmd-[ must restore exact file/revision/caret. Repeat Before and deletion-only
DesktopRuntimeSession.kt (recorded After anchors 3/9); no phantom green added lines.
With tests hidden/manual function folded, an explicit changed-block jump reveals
target and keeps other folds/pins/filters/Critical state. EOF pure add/delete and
no-final-newline shapes are covered by fixtures; use a matching real PR if available,
without modifying tkos. Binary/unchanged/loading disable both. These are manual
requests, not observed results. No actual screenshots exist for this feature.

## 2026-10-06 — Initial changed-code fold defaults

Final binary **14:47:45 PDT**. Actual gates: 227 tests/46 suites, make check/build
swiftbuild, strict deep codesign, env-i /tmp resources (8 grammars/all calls),
clean diff check. No app launch/attachment/screenshots this round: repeated wrong
shared-reader attachment makes another attempt impractical under the user's
limit. This is component/parser evidence, NOT live acceptance. All prior live
PR/hover/outline/filter gaps remain explicit. No tkos/pin/mark/user-reader/branch/
GitHub mutation or commits/pushes; RADIO.png and inactive repo/ preserved.

Core files: Source/ReviewFoldInput.swift; SourceViewerCoordinator/SourceViewer/
SourceScrollView; Syntax/FoldHeaderOwnership.swift and SyntaxWorker+FoldHeaders;
AppModel+PullRequests and ReaderDetail feed exact matched inputs. Fold state
changes occur before one combined layout, with no model.navigate call. Newly
loaded PR document defaults open changed body/block folds and ancestors once
syntax plus hunks match review/path/revision/content in either async order.
Signature-only edits use the owning whole function/closure scope; Rust attributes
and Python decorators use actual Tree-sitter attachments. Sibling closures stay
folded. Unchanged functions/local checkout keep normal defaults. Empty-side
hunks open a containing body, including EOF of unfinished/indentation bodies;
a point outside a closed final body must not implicate its preceding neighbor.
No invented line highlights. Explicit Hide Tests remains the hidden union, not
silently revealed by ordinary-fold defaults.

Manual per-fold choices while pending are respected. Bulk commands while pending
suppress automatic expansion; new coordinators adopt old command revisions as a
baseline. After one-time defaults, manual recollapse stays through later caret,
scroll, index/theme/font/filter updates. New loaded file/revision/review/content
resets the lifecycle. Late layout restores the visible source row/selection
without replaying an old target or reporting a navigation/caret callback. It
cancels obsolete deferred navigation and programmatic-position markers. New
explicit navigation clears older viewport restoration and wins.

Seven new regression cases exercise actual Rust/Python parses, coordinator fold
state and native clip/TextKit layout: header/annotation/closure ownership,
changed/unchanged/nested ancestors; both async orders/manual choices; old/new bulk
commands; stale/new identities/revisions/local defaults; added/removed/empty-side
EOF plus Hide Tests; viewport/selection callback preservation and newer jump;
marker queued then viewport restore then real scroll reporting native current
top and unchanged caret line. The final marker case would fail if stale old
navigation byte intercepted the next scroll. Existing model history/fold/source
mode/pin/copy suites pass. No real PR fold probe was run; recorded PR metadata
below is a manual anchor, recheck SHAs if remote changed.

Manual screenshot/check on fresh signed build: open recorded #724
(head f11c99e3d6/base 488d8768d5) tools/tk-desktop/src/main/kotlin/inc/tk/os/engine/
RuntimeSmoke.kt, previously 17 hunks. Capture After and Before initial view:
changed functions/blocks visible, unchanged functions collapsed. Manually collapse
one changed body, move caret/scroll/change theme or filters, and verify it stays
collapsed. Capture deletion-only DesktopRuntimeSession.kt Before removed 11–64,
After anchors 3/9: removed-containing bodies open in Before; After only containing
point context opens, no phantom green added lines. Added DesktopRuntimeProcess.kt
After bodies open. For Rust/Python annotation-only/multiline header or nested
closure shapes use a matching actual PR if available (fixtures cover them,
never edit tkos to create them). With Hide Tests enabled, changed test code remains
hidden until explicit reveal/Next Change. Trigger Collapse Functions in one file,
open another changed PR file/revision: old command must not recollapse defaults;
new Collapse there must stick. Open late-diff/late-syntax file and scroll before
completion: visible source row/caret/history should remain. If a new jump arrives
before restoration layout, jump wins; Cmd-[ stays exact. Local Checkout retains
normal folding. These remain manual requests, not observed successes.

## 2026-10-06 — Active PR refresh

Final signed binary **20:52:31 PDT**. Actual gates: 234 tests/47 suites,
make check/build swiftbuild, strict deep codesign, env-i /tmp eight-grammar/all-calls
resources, clean diff check. No UI launch/attachment or real gh refresh in this
round: repeated old-reader selection is not practical under user's tooling limit.
No screenshots. Earlier UI/physical-hover/outline/filter gaps remain. Dataset,
user pins/marks/reader, RADIO and inactive repo/ untouched; no commits/pushes,
branch changes or GitHub writes. Temporary Git fixture commits are test data only.

Visible native title+clockwise icon Refresh PR beside selector/Exit PR, mirrored
in menus. Single Cmd-R routes active PR refresh versus outside-PR repository
reload. Refresh List is separate. Refreshing label/subtitle and disabled/coalesced
action, old reader usable until new listing/source succeeds. Same head AND base
only update metadata/recent row, preserving source/history/folds/pins/index.
Changed base with same head refreshes diff/Before honestly. Failure leaves old
reader/root intact; native Try Again carries refresh intent, not open/reset intent.
Exit/cancel/other-PR/repository discard stale completions. Active/candidate UUID
worktree leases prevent eviction, tested at retention limit 1 with failed and
cancelled preparation. Refreshed snapshot commit invalidates all old epochs and
clears SHA-obsolete trails; After index uses existing whole-context cache rules,
Before remains syntax-only.

Latest caret/viewport/pins are captured AFTER mapping reads at commit; moving
paths/bytes retries, and a nil source with pending load awaits/reconciles that
latest request. Exact file bytes retain offsets/current-document pins (including
proven rename remap); otherwise Git blob hunks map lines, keeping column only on
byte-identical mapped line. Other pins/history are cleared on snapshot change.
Valid Before/After choice/options remain, unavailable revision switches with
notice, missing file falls to Changes with reason. Native range/word selection
and manual folds aren't cloned on actual SHA change; new changed-fold defaults
apply. Viewport restoration is best effort source-row preservation, not a claim
of pixel-identical placement.

Seven regression cases pass using FakeGitHub and real temporary Git/worktrees:
metadata-only/no reindex + coalesced context routing; changed head/latest reading/
viewport/options and unchanged attached status; same head/new base/Before plus
deleted-after→Before; network and source preparation failure/refresh retry plus
limit 1 cancellation; deterministic Before-load queued at preparation (old code
would blank reader); proven rename/exact-byte pins/missing former addition;
cancel/Exit/different PR/repository stale completion including cancellation-
ignoring client. An initial failing repo-switch wait compared /var to /private/var;
normalizing aliases fixed the test, not a production-state bug. These are model/
backend/component evidence; no actual remote update, index-generation GUI latency
or native control interaction is claimed.

Core changes: PullRequestModel / ReviewRepository leases; AppModel+PRRefresh and
atomic AppModel.commitPRRefresh; PRRefreshRestoration; byte-proven pin retention;
RootView/PullRequestMenu/ReaderCommands; SourceViewer viewport handoff. Logs:
/tmp/radiology-pr-refresh-review/{test,check,build}.log.

Manual fresh-build check: open a real PR that has received an update (last older
reader observed #753, verify current number/SHAs). Keep a file/caret/viewport,
press Refresh PR or Cmd-R while continuing to read. Capture old readable file
with Refreshing feedback, then latest exact head/base/changes and restored latest
position. Repeat without remote change: document/history/manual folds/pins/index
must remain. Check Refresh List only updates menu, and Cmd-R outside PR reloads
local repository. Simulate unavailable gh/network via normal environment only
if straightforward: capture native refresh error; Try Again must retain refresh
intent and old reader. Cancel/Exit while pending must not later re-enter PR.
Test Before/base update, renamed/deleted/missing file notices and options/filters/
Exit PR/changed-block controls/default changed folds. Full remote snapshot indexing
and pointer/narrow/dark presentation remain manual. Never change tkos/branches
or create a GitHub update merely for this test; use an existing remote update.
