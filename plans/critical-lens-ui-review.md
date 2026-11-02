# Critical Lens native UI review

## 2026-10-04 — Stage one, signed build 15:43:16

GPT Sol exercised the actual signed `build/Radiology.app` through native Computer Use against untouched `/Users/tqbf/codebase/tk/tkos`. Fable did not perform UI runs. The previous Radiology process alone was stopped before launching this build. Screenshots below are actual captures, preserved by the parent in `build/critical-lens-ui-review/stage1/`; links resolve to those copies. Originals remain in `/tmp/radiology-critical-lens-review/stage1/`. `make clean` removes the preserved build directory.

### Observed behavior

- **On-screen drawing works.** In `engine/rust/src/app_image.rs:413–446`, Cmd2 visibly recedes `len`, `Some`, `Err`, `into`, `Vec`, `BTreeMap`, `String`, and other indexed plumbing. Repository operations `section` and `compatibility` remain prominent. Unresolved `Sha256` and `serde_json` remain neutral. Control keywords, braces, literals, and `?` retain normal syntax contrast. Compare [Normal](../build/critical-lens-ui-review/stage1/normal-restore.jpeg) and [Critical](../build/critical-lens-ui-review/stage1/critical-restore.jpeg).
- **System exceptions remain prominent.** In `modules/agent/ffi/src/store_owner.rs:41–49`, `open`, `flock`, `LOCK_EX`, and `as_raw_fd` remain prominent; `last_os_error` recedes. Function shade and current-line tint are still visible, with a thin visible insertion caret at line 41. Existing folded functions and hidden-line badges remain intact. [System operations](../build/critical-lens-ui-review/stage1/system-io-critical.jpeg).
- **Presentation preserves native state in the exercised cases.** Cmd1/Cmd2 changed the selected toolbar segment without moving the file, visible source position, caret or native word selection. Selecting the dimmed `last_os_error` at line 49, copying with CmdC, and pasting into Go to File produced exactly `last_os_error`; the temporary sheet was dismissed without opening anything. Selection and existing fold positions were identical across modes: [Critical selection](../build/critical-lens-ui-review/stage1/selected-critical.jpeg), [Normal selection](../build/critical-lens-ui-review/stage1/selected-normal.jpeg). Back traversed the existing line-navigation departure, then restored `app_image.rs:413` with its original viewport/caret; mode changes did not add intervening history entries. This is visible interaction evidence, not a proof of every byte-offset/history invariant.
- **Marks target actual identity and update drawing.** Right-clicking `Some` at `app_image.rs:414` presented Mark “Some” and Mark Package “core”; its unavailable definition action was disabled. A symbol Critical mark promoted both visible occurrences immediately. [Symbol mark](../build/critical-lens-ui-review/stage1/symbol-override.jpeg). The saved file contained the full SCIP symbol identity and qualified versionless package key `rust-analyzer cargo core`.
- **Precedence and persistence work in both exercised directions.** Symbol Critical plus package Non-Critical survived an app relaunch and repository reopen; `Some` remained prominent. [Relaunch](../build/critical-lens-ui-review/stage1/relaunch-persistence.jpeg). Conversely, package Critical promoted other core plumbing while symbol Non-Critical kept both `Some` occurrences dim. [Opposing marks](../build/critical-lens-ui-review/stage1/package-critical-symbol-ordinary.jpeg).
- The repository remained **Index Partial** throughout and usable. Default Context rows remained concise and source-ordered, with **Definition** rather than “Under Caret”. No new summary/frontier UI is present in this stage.

### Design verdict and scope

Stage one is ready for the graph milestone. The native segmented control makes the active mode clear. The light-mode contrast creates a useful hierarchy: ordinary operations are deliberately faint but remain identifiable when inspected; important operations, syntax and unresolved dependencies dominate the scan. Keep the current 42% light alpha for now. No application changes or rebuild were needed. View menu items lack radio indicators by the implementation contract, but the visible selected toolbar segment made this unambiguous during the pass; no menu change was justified by observed confusion.

No capture blocker occurred. One action immediately after relaunch correctly required a fresh `get_app_state` attachment; attaching succeeded. No custom UI probes, browser automation, permission changes or recovery loops were used.

**Limits:** light mode only; no actual dark-mode judgment, dense `app.rs` pass, pin-overlay test, newly toggled fold test, toolbar-pointer activation test, local-symbol menu exclusion test, alternate-repository isolation test, failed-save footer test, or definition Return test in this pass. Existing folds were preserved, not newly created. Copy was observed through native paste. No internal race/cache correctness is inferred from screenshots. The handoff reported `make check`, 146 tests / 28 suites, build, strict deep codesign and empty-environment resource verification (8 grammars); those gates were not rerun by the reviewer because code/build did not change. Binary timestamp was independently checked as **2026-10-04 15:43:16**.

### Cleanup and stage-two handoff

Before testing, the repository override file was snapshotted as absent at `~/Library/Application Support/Radiology/overrides/98b359c61dd73dfb.json`. After the persistence test the review app was stopped, and only that test-created file was removed, restoring the original absent state. No tkos files or indexes were written. Screenshot artifacts and the snapshot are app-review artifacts only.

Resume Fable for function summaries, resolved call sites and bounded frontier first. Preserve the successful draw-only projection and current reader state; retain concise defaults/disclosures and honest partial/unknown states. Do not infer calls from arbitrary symbol occurrences or manufacture dependency definitions. Then hand over a signed build for native UI review before adding callable hover and visually distinct gutter/outline critical counts. Useful remaining stage-one checks during that pass are dark contrast, a pin over an ordinary token, and `app.rs:1157` / `2058` density. They are follow-up coverage, not known failures.

## 2026-10-04 — Final milestone build 16:19:59: native attachment blocked

The signed final build was launched with `--repository /Users/tqbf/codebase/tk/tkos --file engine/rust/src/app_image.rs`. There was no pre-existing Radiology process in the exact executable-path check. The binary timestamp was independently checked as **2026-10-04 16:19:59**. Native Computer Use `get_app_state` using `org.sockpuppet.radiology` failed with **Computer Use server error -10005: cgWindowNotFound**. The one permitted recovery using the full `.app` path failed identically. UI work stopped immediately, without diagnosing tooling, restarting, or building custom probes. No source edits, tests or builds were performed. No final-build screenshot or AX evidence was obtained; no final feature acceptance is claimed.

The root/index/design documents were read for the current contracts. Handed-off gates are **161 tests in 32 suites**, `make check`, swiftbuild signed build, strict deep codesign and empty-environment packaged resource verification for eight grammars including calls queries. Those are separate reported model/build evidence, not live UI verification. The stage-one screenshots remain preserved under `build/critical-lens-ui-review/stage1`; they cannot establish the final summaries, hover or badges.

The override snapshot at `/tmp/radiology-critical-lens-review/final/override-snapshot.json` records the original absent state; it still matches after the failed attachment. No marks were changed and tkos was untouched. There are **no final screenshot artifacts** to preserve. The launched app was left available for manual inspection.

### Precise manual acceptance and screenshot requests

1. Open `engine/rust/src/app_image.rs`, CmdL **401**, click inside `restore_app`, Cmd2. Capture the whole window with upper Critical **restore → 404**, references below it, and the independent lower Definition/frontier. Move into `restore` **404**: capture **section ×3**, **compatibility**, and partial coverage, with names visible without disclosure. There must be no “Under Caret” heading or verbose default source blocks.
2. At **404**, right-click the actual `restore` name and choose Mark “restore” → Non-Critical. Return to **401**. Capture the two distinct frontier rows **section via restore** and **compatibility via restore**; expand a chain and capture it. Expansion must not navigate. Activate a real location/selected row Return, then Cmd-[ must restore the departure caret/file/viewport. Reset Mark “restore” → Built-In and verify the original absent override state (no repository writes).
3. At **413**, click inside `section`, then hover the name without modifiers. Capture the automatic compact popover and its Definition link. Move the pointer into it: it must stay open long enough to click Definition. Verify **93**, then Cmd-[ returns to the exact **413** departure. Also activate a reachable row from sidebar/popover and verify Back. Passive hover/selection must never navigate. Hover `libc::flock` in `modules/agent/ffi/src/store_owner.rs:48`: capture honest external/no-body state with no guessed navigable definition.
4. Collapse `restore` from its gutter disclosure. Capture the **2+ accent-stroked square** and its tooltip showing hidden-line count. Capture source-ordered outline counts, a quiet proven **0**, and a distinct **–** no-body annotation if available in real indexed data; do not manufacture a fixture just to obtain the latter. Toggle Cmd1 and capture the ordinary hidden-line capsule/reference presentation, then Cmd2: caret, viewport and fold state must survive.
5. Open `modules/agent/ffi/src/app.rs`, visit **1157 publish_instructions**, **2058 read_observation**, and **1343 open**. Capture each default upper/lower region: useful call names, honest unknown/conditional/partial states, no sea of expanded text. `read_observation` should expose `observe_session`. Scroll the dense `open` list and check responsiveness. If a simple divider drag permits **220pt**, capture the narrow inspector with readable names/locations and no overlap.
6. Select/copy a dim token, pin an occurrence using the existing pin UI, and toggle Cmd1/Cmd2. Capture the caret/current-line/function-shade/pin layering and verify no reader-state/history changes. Source Return on `section:413` and sidebar Return must still navigate with exact Back. Dark mode only if already straightforward: capture source, badge and hover contrast; do not spend time on tooling or system-setting workarounds.

**Final verdict:** stage-one native acceptance remains valid; final summaries/frontier/hover/counts are **unverified because attachment was blocked**. No concrete final-build product defect was observed. The milestone needs the manual checks above or a later successful bounded native session before it is called visually accepted.

## 2026-10-04 — Call-focused projection, signed build 16:53:36

The user explicitly superseded the earlier rendering contract: dim most syntax,
strings/constants, locals/receivers/fields, types and declarations so only
function-call names pop. The supplied screenshot was inspected and its actual
case located at `modules/agent/ffi/src/app.rs:115–139`, `execute_future` (not
`debug_trace/pipeline_tests.rs`). The original user screenshot is preserved as
[user before](../build/critical-lens-ui-review/call-focus/user-before.png),
separate from reviewer captures.

### Implementation and validation

`CriticalProjection` now complements the valid Tree-sitter named-call ranges
over the exact source bytes. Only critical/unknown actual call-name tokens
remain full contrast. Resolved ordinary runtime calls stay dim; syntax-only
unresolved calls can remain prominent without semantic identities or fabricated
graph edges. Non-call marks cannot promote fields, constants or declaration
names. Macros use the existing call-query name capture; opaque macro arguments
and unsupported computed callee shapes are not guessed. Classification,
summaries, frontier and renderer abstractions are unchanged. Missing semantic
data now permits syntax-only projection; absent call syntax leaves Normal
rendering until structure is available.

Context alpha is **30% light / 38% dark** (formerly 42% / 50% for ordinary
identifiers only). Font size, weight, syntax role color, source storage, layout
and coordinates stay unchanged. Normal restores the full reading contrast.
The old protect-all-syntax design and tests are superseded; README and design
contracts were updated. swiftui-pro, macos-design and typography-designer were
applied to the decision and post-change review. No new view/focus/navigation
logic or font hierarchy was introduced.

Meaningful tests cover repository call versus declaration/receiver, ordinary
calls, unresolved actual calls, comments/string spellings not becoming calls,
pattern constructors, critical non-call marks staying dim, Unicode UTF-8 to
UTF-16 boundaries, exact-source matching, and an unindexed file producing no
semantic navigation target. Existing model/drawing/reader regressions cover
state preservation. The first full run exposed an existing timing-sensitive
cache regression: parsing the mutated viewer bytes under parallel load could
outlast its artificial 150ms disk delay. Preparing those bytes before starting
the race restored the intended test interleaving; assertions were preserved,
and production graph code was not changed. An initial run was interrupted
while outdated test expectations were being replaced; it is not counted as a
passing gate.

Final gates actually run: **make check**, **make test: 163 tests / 32 suites**,
**make build (swiftbuild)**, **codesign --verify --deep --strict**, and packaged
`--verify-resources` from `/tmp` with `env -i`: all eight grammars loaded
highlights/folds/symbols/scopes/calls. Signed binary timestamp independently
checked: **2026-10-04 16:53:36**. RADIO.png and Make icon generation were
preserved. No tkos writes, commits or pushes.

### Actual native evidence and acceptance

Native attachment succeeded on the first attempt for this build. CmdL brought
the actual `app.rs` reader to the `execute_future` region; the expanded body
was captured at the same visible position in both modes:

- [Normal](../build/critical-lens-ui-review/call-focus/execute-future-normal.jpeg)
- [Call-focused Critical](../build/critical-lens-ui-review/call-focus/execute-future-critical.jpeg)

The contrast difference is visible on screen: declaration `execute_future`,
`async fn`, `let`, `if`, `return`, `await`, receivers/fields/types, literal text
and punctuation become quiet context. `from_value`, `new`,
`execute_durable_input`, `map`, `map_err`, `to_message` and `text` form the
foreground where syntactic and non-ordinary. Proven ordinary `upgrade`,
`ok_or_else`, `to_owned`, `Some` and `format` stay faint. Dim strings/control/
locals can still be made out when inspected, but are deliberately low contrast;
Normal is the full-reading view. Existing colored locked pins on `engine`,
`transcripts` and `kind` remain visible while their text recedes, and the
current-line wash remains visible. These pins were already present in the
shared reader; the reviewer did not create or change them. The same viewport,
line position and pin placement survived the captured mode switch.

The upper automatic Critical section visibly contained concise names and
`5 direct · 7 conditional · partial`, plus unknown/closure caveats, ahead of
References. The lower Definition independently showed the selected `engine`
field. No “Under Caret” label appeared. This closes actual evidence for that
sidebar presentation in this case, not all previous graph acceptance cases.

**Separate user evidence:** while this pass was underway the user said
**“this is much better”**. Treat that as acceptance of the aggressive rendering;
it is not a substitute for reviewer observations or a proof of dark contrast.
The user then asked about right-click marks; the existing indexed-symbol
Critical / Non-Critical / Built-In and package behavior was explained by the
parent. The reviewer reached a context-menu attempt only, with no mark-setting
action. No test override values were applied or undone. A snapshot at
`/tmp/radiology-critical-lens-review/call-focus/override-snapshot.json` recorded
absence at test start; no whole-file restore was performed over possible user
decisions.

### Scope and limits

The user was interacting with the same reader; native state shifted and the
tool required a refresh. After the requested steering, live work stopped to
avoid competing with the user's navigation. No recovery loop or custom probe
was used. Dark mode, fresh mark promotion/demotion, hover → enter → Definition
→ exact Back, folded-count semantics, and full earlier frontier traversal were
**not verified in this pass**. Existing stage-one mark persistence evidence is
historical, not a new call-focused live mark test. No further contrast redesign
is needed following user acceptance. Current verdict: call-focused light-mode
rendering is visually successful and user accepted; remaining milestone UI
gaps retain their explicit unverified status.

Actual new artifacts are under `/tmp/radiology-critical-lens-review/call-focus/`;
the parent preserved the supplied screenshot and both native comparison captures
in `build/critical-lens-ui-review/call-focus/`. Links above resolve to those
copies. `make clean` removes that build directory. No screenshots or UI results
were invented.

## 2026-10-04 — Lens depiction removed from sidebar, build 17:05:05

The user requested removing the sidebar depiction because it was not paying
its freight. The upper Critical call/frontier/status/unknown/conditional section,
lower callable frontier and outline density counts are removed. Both source
modes now use the existing concise declaration/references and Definition/outline
sidebar, disclosures and reference/definition navigation. There is no
replacement lens summary. Call-focused source projection, toolbar mode control,
persistent marks, source hover frontier and fold-gutter counts remain.

Unused CriticalCallsContent, CriticalFrontierView and CriticalCallRow components
were removed, along with sidebar phases/tasks/keys/counters, via expansion
state, critical list-ID dispatch and symbol-annotation publication. Hover keeps
its compact rows and real-definition links; their two small formatting helpers
are now local to the hover view rather than retaining unused sidebar components.
The annotation sweep considers only callables with source folds. Pointer dwell
still computes hover frontiers and primes current reader bytes before traversal;
caret identities schedule no summary requests. Generic CountAnnotation remains
for the gutter. No source text/storage/layout changes, new sidebar design or
classification/graph changes were introduced.

Regression evidence: mode changes preserve declaration/Definition identities,
reference results, selection/disclosures and navigation state; reference commit
and exact Back still work in Critical; moving the caret after gutter work
settles creates no additional summary builds or annotation runs; outline-only
abstract declarations with no source folds schedule no work. Existing hover
retention/closure/external-state and gutter mark-refresh/stale-result tests
continue to pass. Required swiftui-pro, macos-design and typography guidance
were applied before and after the removal; surviving type roles are unchanged.

Final actual gates: **make check**, **164 tests in 32 suites**, **make build
(swiftbuild)**, strict deep codesign and empty-environment packaged resource
verification from `/tmp` (**8 grammars**, all calls queries) passed. Signed
binary timestamp: **2026-10-04 17:05:05**. RADIO.png/icon pipeline preserved.
No tkos writes, marks changed, commits or pushes.

**Live limit:** no app relaunch or native interaction was attempted for this
removal because the user was browsing the shared reader. No new screenshots
or actual visual acceptance are claimed. This avoids displacing their file,
caret, pins or mark state. The earlier call-focused rendering remains accepted;
this sidebar change has model/build evidence only. A brief later check is to
place the caret on `section` at `app_image.rs:413`, compare Cmd1/Cmd2, and
capture the same declaration/references plus Definition sidebar with source
call focus changing and no lens rows/counts. It does not require repeating the
historical hover/gutter matrix.

## 2026-10-04 — Clickable hover targets and native retention, build 17:21:39

The user reported visible symbol definition/reference popups that could not be
clicked. All source symbol-hover paths were inspected. The source has one
custom Critical `NSPopover`; there is no native source-symbol tooltip or
`.toolTip` navigation implementation. Gutter tooltips and ordinary `.help`
strings are explanatory only. The popover lists definitions and critical
frontier callees, not reference occurrences; no new references UI was added.

### Source-confirmed problems and changes

The hovered title and frontier call names were plain `Text`; only narrow
trailing Definition/location links were buttons. Clicking the obvious name
therefore did nothing. Every row with a real indexed definition is now a
**whole-row Button**, including name, spacing and trailing detail, with accent
foreground and an explicit accessible destination label. External/missing
rows have no button and remain honestly unavailable. No tooltip or guessed
identity is used for navigation.

The old retention depended on SwiftUI `.onHover` plus a 250ms exit grace, and
loading-to-loaded publication replaced the hosting root view. The fix uses a
stable observable content object inside one host, native AppKit tracking over
the entire popover (padding and buttons, active even when the source window
loses key status), and a screen-space anchor-to-popover transit region. Source
mouse movement in that region retains the popover instead of replacing it on
another semantic token en route. Popover entry cancels pending replacement and
close tasks; exit has a 700ms grace. Outside click/key/scroll/context-change
semantics remain. These retention vulnerabilities were found in source;
**their contribution to the user's actual pointer failure was not reproduced
live**. Navigation remains the existing indexed-definition/exact-caret path.

No removed sidebar summaries/counts were restored. Aggressive source dimming,
marks, source gutter counts, concise normal Context, RADIO.png and icon pipeline
are preserved. No tkos writes, mark edits, commits or pushes.

### Regression evidence and gates

Native AppKit regressions verify that the hosting view actually installs a
full-area activeAlways tracking area, retains the same view across result
publication, routes native mouse-enter/exit events, and covers the source/
popup gap while excluding distant source. The model regression additionally
checks that another callable cannot replace a popover while the pointer is
inside it, and that activating its real destination then Back restores the
exact departure caret. These are separate native/model tests, **not a claim
of physical button click acceptance**. A attempted offscreen SwiftUI AX button
press test could not obtain the bridge's button tree and was not retained as
false evidence; actual pointer clicks remain the manual gate.

Required skills swiftui-pro, macos-design and typography guidance were read
and applied before/after the changes. Surviving system type hierarchy is
unchanged; semantic Buttons replace passive text, and native tracking is
confined to the AppKit popover host.

Actual final gates all pass: **make check**, **166 tests / 33 suites**,
**make build (swiftbuild)**, strict deep codesign, and `--verify-resources`
from `/tmp` under `env -i` (all eight grammars, including calls queries).
Signed binary timestamp: **2026-10-04 17:21:39**.

### Native access limit and precise manual check

An initial native read of the existing reader succeeded. For the fixed build,
a separate fresh review process was launched with tkos `app_image.rs` to avoid
closing the user's reader or losing its in-memory pins. Computer Use by bundle
ID attached instead to the pre-existing `app.rs:316` window. The one full-app-
path recovery selected that same old window. UI interaction stopped, and only
the explicitly launched review process was terminated. The user's original
reader was not closed by the reviewer. No additional attachment attempts or
custom UI probes were made. The native API also exposes no dedicated pointer-
hover/move action; no workaround was built.

**Exact blocker:** fresh-instance selection failed in native Computer Use;
there is no physical hover-entry/click evidence for this signed fix. No popup
screenshot was captured. The tool's old-window screenshot URL subsequently
expired before preservation, so `/tmp/radiology-critical-lens-review/clickable-hover/`
contains no actual new screenshot artifacts. Do not use an old reader capture
as proof of the fix.

After reopening the signed build when the user is ready:

1. Open `engine/rust/src/app_image.rs`, go to **413**, place a caret inside
   `section`, Cmd2, then move the pointer off and back onto `section` without
   modifiers. Capture the popup with its clearly actionable **section / Definition**
   row. Move through the gap into the popup and click the **name** (not just
   the trailing word). Verify definition **93**, then Cmd-[ restores the exact
   **413** caret/file. Hover alone must not change source position/history.
2. At **401–402**, hover `restore` in `restore_app`; capture its popup, move
   into it, and click the offered `section` frontier row by its name. Verify
   **93** and exact Back to departure. Also click the title to **404** if
   straightforward. These are real definition entries, not reference hits.
3. Hover `libc::flock` at `modules/agent/ffi/src/store_owner.rs:48`; capture
   unavailable external/no-body content and verify no clickable guessed
   destination. Do not change marks or run a broad historical matrix.

**Verdict:** the confirmed passive-name hit-target defect is repaired and the
retention mechanism has native regression evidence; physical click/Back
acceptance remains unverified due the specific fresh-instance attachment limit.

## 2026-10-04 17:35 — Ordinary outline size ordering

Implemented the user's function-first outline request, identical in both modes.
All Tree-sitter callable declarations are flat and sorted descending by inclusive
signature-to-end line span, with source-order ties. Non-callables follow in a
native hierarchy; callable entries are not duplicated. Original IDs/ranges and
navigation actions are retained. Counts use existing Theme.Fonts.meta with quiet
secondary tabular digits; names are one line with middle truncation. Composite
path/content/symbol invalidation handles identical files at different paths.

Check, 169 tests/34 suites, signed swiftbuild bundle, strict deep codesign and
empty-env 8-grammar/all-calls resource verification passed. Binary 17:35:04 CDT.
Native get_app_state attached to old app.rs instead of the separately launched
fresh app_image review instance. Stopped immediately, without interacting with
or replacing the user's reader. Only the review instance was terminated. There
are no new screenshots or observed outline appearance/navigation outcomes.
The earlier popup physical-click/retention limitation is NOT resolved by this
round; its manual checks still apply. Design judgment is source-level only:
one-line native rows and quiet trailing sizes should support scanning, but narrow
appearance and native selection must still be visually checked.

Manual outline check on the signed build: open tkos modules/agent/ffi/src/app.rs,
place the caret on whitespace so the lower region shows Outline, and scroll its
list to the top. Capture functions/methods first with descending `n L` counts;
methods should be immediately accessible without expanding impls. Scroll through
to Declarations, expand containers and confirm no duplicated functions while
nested non-callables remain. Capture at 220-point inspector width: names/counts
must remain single-line without overlap. Activate one function, then Cmd-[ to
check exact departure; repeat Cmd1/Cmd2 on the same view to confirm identical
outline ordering/counts while source projection changes. These are manual tasks,
not claimed live successes. No tkos writes or mark/pin changes were made.
