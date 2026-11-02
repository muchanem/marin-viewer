# Source filters UI review

## Preparation — 2026-10-04, GPT Sol (read-only app/dataset)

Baseline 186 tests/39 suites, signed 20:18:12 CDT. Opus owns application source,
builds and normal docs until handoff. No launch, UI attachment, build, tests or
source/dataset edits in this preparation. source-filters.md was not present at
first read; did not poll it. Prior PR/outline/physical-hover live limitations
remain explicit and do not become passes for this milestone.

Required skills: swiftui-pro (observation/invalidation, native Buttons, no text
coordinate rewriting), macos-design (two discoverable independent native filters,
concise feedback/empty states), typography-designer (existing Theme semantic
roles; quiet counts and accessible names rather than new type scale).
Existing folds use canonical bytes converted at TextKit, sorted disjoint hidden
UTF-16 ranges, and explicit reveal removes enclosing folds. Inline test hiding
must cooperate with this mapping/reveal contract without rewriting source.

### Actual read-only tkos anchors

- modules/agent/ffi/src/app.rs:35–43 cfg(test) external test-module declarations;
  production constants follow at44+. Ensure attributes/path declarations hide
  together without consuming production comments/constants.
- app.rs:803 cfg(test), detached_for_test signature804–807 through closing833;
  production create_durable_agent starts834 immediately afterward. This is the
  primary mid-file boundary/reveal/caret case, with no separating blank line.
- app.rs:3424 cfg(test) inline tests module,3428 test attribute,3429
  none_effort_is_preserved_by_the_json_bridge;3435 next attribute,3436
  durable_agent_wake_links_board_author_and_keeps_state_across_sessions.
- engine/rust/src/snapshot_policy.rs:9 configure remains production; cfg(test)
  module16–17 contains helper child21 and annotated test41–42. Ignored test
  has attributes54–55 and snapshot_process56. Hide owning module/helper too.
- fonts/src/test/kotlin/inc/tk/os/fonts/FontFilesTest.kt:9 class;12 @Test
  simultaneous-demand test,27 second @Test,43 third. Compare production
  fonts/src/main/kotlin/inc/tk/os/fonts/FontFiles.kt in Files browsing.
- scripts/test_pr_local.py:22 PrLocalTest(unittest.TestCase),70 test_fetches_main…,
 78 test_conflict_free_merge…; scripts/pr-local.py is production counterpart.
- scripts/home-design-inspect.test.ts:22 first test,31/39 subsequent tests;
  scripts/home-design-inspect.ts is production counterpart.

### Focused acceptance at signed handoff

1. Two independently discoverable controls: Hide Tests versus source-only Files.
   Toggle each alone and both; accessible state/labels/help remain clear. Filters
   must not silently change repository, source mode, caret/history or mark state.
2. Source-only Files: exclude generated/non-source artifacts, prune empty folders,
   retain relevant source/test files according to separate Hide Tests state.
   Current filtered-out open file remains readable/identified; file-query no-match
   has useful empty state. Changes/Search scope must follow actual contract, not
   an assumed global exclusion. User fixtures may supplement missing cases.
3. app.rs803–834: Hide Tests skips the complete marked declaration including
   attributes;833→834 boundary does not hide production. Restore exposes exact
   text/line numbers. Top cfg modules35–43 and nested module3424 also disappear.
   Show concise hidden-region/reveal affordance, no overwhelming prose.
4. Explicit Go to Line804/3429, search/outline/reference/definition target into a
   hidden region must reveal correct target and exact Back departure. Keyboard
   arrow movement must not trap in invisible bytes or spuriously navigate.
   Manual function folds remain independent through hide/show/reveal; no stacked
   markers, bad gutter counts, changed copy bytes or Unicode caret displacement.
5. Kotlin/Python/TS best-effort classification uses actual parsed/file evidence;
   honest limits for unsupported shapes. Hiding tests must not hide production
   merely because names contain test (supplementary fixtures if needed).
6. Normal/Critical, subtle caret/current-function shade, selection/copy, user pins
   remain readable and stable. Do not overwrite shared-reader marks/pins.
7. PR Before/After exact-byte highlights, mapped toggle/Back and visible Exit PR
   coexist; deleted/test-only files and explicit hidden targets stay accessible.
   Filter choice must not map After semantics onto Before or mutate repository.

Native check only after signed handoff: one attachment plus at most one simple
recovery within 2–3 minutes. If old shared reader selected/errors persist, stop
without interaction; report exact blocker and request screenshots of controls,
app.rs803–834 hidden/revealed, pruned Files/current-open-file retention, and
PR Before/After with Exit PR. No custom probes/window-selection workaround.
All items above are planned checks, not observed feature verification.

## Signed handoff review and repairs — 2026-10-04 23:23 CDT

Signed 23:16:01 build launched as a separate review instance, tkos app.rs. Native
bundle-ID attachment selected user's existing #691 nomex_e2e.rs PR reader; one
full-path recovery still selected that old window (its scroll state changed
without our interaction). Stopped immediately, no clicks/keys, no screenshots.
Terminated only review PID 60963; user PID 31152 remained. Native budget closed;
final repaired app was not launched. No marks/pins/defaults or tkos changes.

Root source review found four real correctness issues, now fixed by Sol:
pytest test_* is narrow (testing_helper/testify/testConnection preserved);
Vitest if with production else stays wholly visible; hit IDs refresh even when
label rectangles match across documents; actual header glyph visibility gates
painting/hits. AppKit regression confirmed character-range mapping can expand a
hidden header to the surviving parent-fold row. Test now proves no label/hit
while outer function folded, label present after expansion. Separate same-rect,
new-byte-ID regression verifies the click resolves the new region. These are
native component tests, NOT observed live UI. Extra history-doc EOF blank removed.

Final gates independently run: make test 213/43, check, make build swiftbuild,
strict deep codesign, env-i /tmp eight-grammar/all-calls resources, clean diff
check. Signed binary **2026-10-04 23:23:22 CDT**. Two opt-in real tkos probes
(inline anchors, Files filtering) pass on repaired source. Opus's full 63-second
sweep was not repeated; its three opt-ins are separate historical evidence.

Source-level design verdict: two independent accessory-bar icon Toggles, native
selected state, descriptive help/accessible labels, checked View menu items and
shortcuts are coherent with a concise navigator. Existing Theme type roles serve
footer and reveal counts. Their visual discoverability, tint/contrast, hit sizes,
narrow layout and VoiceOver output remain unobserved; no speculative polish added.

Manual screenshots/checks on the fresh signed app:

1. Files at normal/narrow width: capture both toggles off and on (independently),
   selected state/help and View checkmarks. Source Only excludes README/build
   artifacts; Hide Tests excludes FontFilesTest.kt/test_pr_local.py/test TS paths;
   both retain production counterparts and prune empty directories. Keep an
   explicitly opened excluded file readable, with footer warning. A no-match
   query shows useful empty state and Show All Files resets filters.
2. app.rs at803: Hide Tests shows dim header and Test code label; next source
   line is834 create_durable_agent. Capture hidden then label/gutter-revealed
   helper;35–43 then44 and3424+ module are independent boundary checks. Go to
   Line804/3429 must reveal; Cmd-[ returns exact departure. Repeat with manual
   outer/function folds, arrows, selection/copy and Normal/Critical: no invisible
   caret trap, accidental navigation, label on hidden ancestor or changed bytes.
3. Open whole Kotlin/Python/TS test files via Cmd-K: full readable document with
   Test file footer despite hidden Files entries; production counterpart stays.
   Filtered-tree expansion remains across option changes/reload. Preserve user
   pins/marks; do not reset a whole old state snapshot.
4. PR Before/After with filters enabled: exact mapped caret/Back, canonical added/
   removed lines, unchanged Changes list and visible Exit PR. Before never uses
   After semantics. This is manual; prior PR/outline/hover gaps are not passed.

No actual screenshots exist for this round. UI acceptance remains open because
fresh-window attachment failed; all pass claims above identify backend/component
scope. Preparation evidence above remains intact.

## 2026-10-05 — PR Changes filtering fix

User superseded the prior Changes-unfiltered scope. Shared includes policy now
filters Changes with both options; full review.changes remains canonical. Deleted
uses Before. Rename/copy retained if either available Before or After path passes
both active options, so a production-source→Markdown/test path move stays visible
when its original source passes. Original PR order is retained. Compact native
filter toggles appear in Changes header. Header/footer counts describe visible
changed files of total PR files, +/− totals only visible text-file rows (tooltip
clarifies binary unavailable). Filtered-empty No Changes to Show has Show All Files;
genuinely no changes remains distinct. Selection updates only among visible rows
and skips navigation when syncing the current open document.

Actual gates: 216 tests/44 suites, make check/build swiftbuild, strict deep
codesign, env-i resources from /tmp (8 grammars/all calls), clean diff check.
Signed binary **2026-10-05 19:00:13 PDT**. Mixed markdown/code/test/build,
independent toggles, deleted/rename extension/test-path directions, source order,
visible totals, empty distinctions, selection reset and excluded Before-reader
preservation are regression-tested. No UI attempt or screenshots per user's
explicit bounded-tooling request. No dataset/defaults/pin/mark/reader mutation;
previous visual/hover/PR/outline gaps remain open. Native/type skill review kept
existing Theme body/meta roles, native Toggles/List/empty-state Buttons.

Manual check: on fresh signed build open a PR with Markdown and source (recorded
#724 head f11c99e3d6 has docs/dev/desktop-runtime-*.md, Python, TS tests and Kotlin).
In Changes turn Source Only on: Markdown/config rows disappear; counts/totals
shrink to visible rows. Add Hide Tests: test rows disappear; both toggles remain
independent. Capture header/list/footer and both states. Open Markdown first,
place a caret or switch Before, then filter: reader/caret/revision/history must
remain, without another row opening. Turn filters off: selection resyncs without
navigation. Exercise a deleted source row and extension-changing rename (fixture
regressions supply those shapes if current PR lacks them); capture filtered-empty
with Show All Files separately from genuinely empty PR. This is an exact manual
checklist, NOT claimed live evidence. Prior prep's unchanged-Changes assertion
is historical and superseded; search/picker/indexing remain unfiltered.
