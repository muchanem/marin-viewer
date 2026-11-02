# Context inspector: native UI review

Latest 2026-10-08 layout supersedes the fixed split/type hierarchy reviewed below.
See [inspector-refinement.md](inspector-refinement.md) for top-stacked sections,
dominant symbol, faint tints, current native reference navigation and gates.
The following review remains historical evidence for the original implementation.

## Final signed build targeted recheck — 2026-10-04

This section supersedes the initial defect status below. Parent reported the
13:31 rebuild and 123 tests / 19 suites, signing and packaged-resource gates;
these were not rerun by this reviewer. Terminated only the existing Radiology
PID 25148 and launched the fresh signed app on the same untouched tkos root,
with `--file modules/agent/ffi/src/app.rs`.

**Three of four repairs are visibly confirmed. The fourth is unverified due
to a native capture failure; no remaining product defect was demonstrated in
this targeted recheck.**

- **Pinned multiline signature: repaired.** Clicking `open` at 1343 shows
  multiple upper signature lines at the default approximately 240-point
  width. With inspector widened to approximately 360 points and upper split
  enlarged, all seven canonical signature lines (1343–1349), including return
  type, are visible while the reference list and call-site preview remain
  usable. Narrow wrapping can truncate the bounded signature appropriately.
- **Reference preview height: repaired.** Selected reference 763 displays
  numbered call-site lines 761–765 at default and enlarged split heights.
  At approximately 220-point width and upper region reduced to approximately
  220 points high, it condenses to the numbered call-site line 763 rather
  than disappearing. A separate scrollable list area remains visible. Exact
  72-point minimum was not measured through AX; screenshot evidence confirms
  separation but does not prove the specified metric. No collapsed code
  preview or oversized overlap was observed in these tested sizes.
- **Adjacent definition boundary: repaired.** `runtime.rs:145` restore_app
  preview visually and through AX contains only `app_image.rs:401–403`.
  Clicking the definition link goes to401; Cmd-[ returns to145 and the same
  restore_app token/context. The next declaration at404 is absent.
- **README wording: not verified on final build.** Opened Go to File and
  entered README.md. During the subsequent state/Return/state sequence,
  ScreenCaptureKit failed before final evidence could be returned. Do not
  infer whether the file opened or which label it displayed. Parent manual
  check: Cmd-K, README.md, wait for root match, Return; screenshot lower
  “File not indexed” beside Outline and footer “Index Partial”.

Native recovery boundary: initial attachment succeeded. A later divider drag
returned `Computer Use server error -10005: noWindowsAvailable`; the single
immediate bundle-ID state retry recovered, and ordinary keyboard/click tests
continued. The final README sequence returned `Computer Use server error
-10005: Error Domain=com.apple.ScreenCaptureKit.SCStreamErrorDomain
Code=-3812 "Failed due to an invalid parameter"`. UI work stopped immediately
without another retry, restart, permission change, or workaround. Cmd-click,
unselected-row context menu, and long-reference-list scroll retention were
not exercised in this recheck. Initial limitations below otherwise stand.

New actual captures preserved in `build/context-ui-review/recheck/` (removed by `make clean`):

- [Default pinned open signature](/Users/tqbf/codebase/radiology/build/context-ui-review/recheck/open-default.jpeg)
- [Default numbered reference preview](/Users/tqbf/codebase/radiology/build/context-ui-review/recheck/reference-default.jpeg)
- [Enlarged split: complete seven-line signature and preview](/Users/tqbf/codebase/radiology/build/context-ui-review/recheck/reference-enlarged.jpeg)
- [Short split at 220-point width: condensed numbered call site](/Users/tqbf/codebase/radiology/build/context-ui-review/recheck/reference-short-220.jpeg)
- [Definition preview restricted to401–403](/Users/tqbf/codebase/radiology/build/context-ui-review/recheck/restore-app-boundary.jpeg)
- [Back to original restore_app call](/Users/tqbf/codebase/radiology/build/context-ui-review/recheck/restore-app-back.jpeg)

Final design verdict: the three observed layout/preview defects are resolved
in the tested sizes. The inspector now keeps summary, reference list, and
preview distinct, with sensible native type hierarchy and compact behavior.
Final acceptance still needs the one README label screenshot. This reviewer
changed only this document and saved native captures; no application source,
builds, PLAN, PROGRESS, or tkos files were changed.

Reviewed 2026-10-04 using the signed `build/Radiology.app` supplied by Opus,
against the untouched `/Users/tqbf/codebase/tk/tkos` repository and its real
app-owned SCIP cache. The existing Radiology process (PID 19713) was terminated
and a fresh instance launched with `--repository` and
`--file engine/rust/src/app_image.rs`. No application code, tkos data, parent
documentation, build output, or dependencies were edited by this reviewer.
Opus's reported 120 tests / 19 suites and signing/resource gates are separate
evidence; this review did not run builds or tests.

Applied local swiftui-pro, macos-design, typography-designer, and native
computer-use guidance. All UI actions used `@oai/sky` through node_repl.
Initial screenshots below are actual native captures, now preserved by the parent
in `build/context-ui-review/initial/`.

## Observed successes

- Source at `app_image.rs:94`: click inside `input`, then ordinary Left/Right
  keys moved the read-only NSTextView caret. Lower context showed `input`, its
  parameter signature, definition at line 93, and five file occurrences.
  One Left within the token yielded no AX-tree change. Moving beyond the
  half-open token boundary restored Outline. Upper `section` stayed stable,
  with three references and a separately marked definition (four file rows).
  This demonstrates visible stability, not internal query/cache counts.
- Single-click line 413 followed by Down selected line 420 and displayed a
  separate call-site preview. Main source and footer remained at line 94.
  Return committed line 420; Cmd-[ restored line 94 and the original `input`
  context. No passive preview navigation was observed.
- `runtime.rs:145` `restore_app` showed its signature, definition link to
  `app_image.rs:401`, and real numbered preview. Clicking the link navigated
  across files; Cmd-[ restored line 145 and the original token context.
- `app.rs:4288` `read_observation` showed definition at 2058 and numbered
  preview. Tab from source reached the upper reference list; a second Tab
  reached the lower focusable region (visible focus ring, although AX did not
  name that focus). Return navigated to 2058; Cmd-[ restored the selected call
  at 4288. Passive source scrolling two pages down left both Context regions
  tracking the original caret. Clicking the lower definition afterward and
  using Back again returned to 4288, rather than the scrolled viewport.
- Actual large default fold at `app.rs:1343–1349` retained its multiline
  signature rows and 279-line body badge. Clicking `open` selected the correct
  method, replacing the enclosing impl context with four references. Lower
  signature was multiline and dedented. Clicking `args` then `executor_id`
  independently changed local details while preserving selected reference
  `app.rs:763`, the upper summary, and reference-list state. A scroll gesture
  in this short list did not move its contents; retention of a substantially
  scrolled long reference list remains unverified.
- Inspector divider moved from x=911 to x=930 in a 1152-pixel screenshot,
  giving approximately 220-point width. Names and kind/location metadata
  stacked sensibly; lower signature and preview remained contained and
  scrollable. The native vertical split divider also moved successfully.
- `Some` at `runtime.rs:145` honestly displayed “Defined in core, outside this
  repository. Its source is not indexed, so there is no preview.” No definition
  link appeared. Missing signature was not fabricated. Double-click selected
  the word and AX reported one pinned group / 45 pinned occurrences; Cmd-C was
  dispatched normally. Whitespace restored Outline while pins persisted.
  Clipboard bytes were not inspected, so copied-content correctness is not
  claimed.
- Opening root `README.md` cleared declaration, semantic symbol, selected
  reference, and preview. Native empty states explained missing structure.
  No old Context contents remained. The footer continued to report Partial.
- AX exposed actual numbered preview text as Details, confirming the prior
  code-text accessibility omission was repaired at the AX level. VoiceOver
  speech itself was not exercised.

## Defects observed in this build

1. **Pinned signature is compressed to one line.** At `app.rs:1343`, upper
   `open` renders only `fn open(…`, while lower context shows multiline
   parameters. There is substantial unused reference-list space. Increasing
   upper-region height does not recover the multiline pinned signature.
   Source-level likely cause: higher layout priority on the List permits the
   pinned Text to compress. Preserve an intentional multiline summary height;
   keep the list scrollable within its remaining space.
2. **Reference snippet collapses completely.** Selecting `open` call at
   `app.rs:763` shows location/hint/Open but no code snippet at the default
   split height. Enlarging upper region to roughly 470 points still leaves
   only the preview header with empty list space above. This also occurred
   with the `section` call-site preview: its AX tree contained numbered text,
   but the screenshot showed only preview controls. A max-height cap without
   a usable minimum/ideal height on the ViewThatFits/ScrollView appears to
   permit a zero-height code area. Ensure a visible excerpt and scrolling.
3. **Adjacent declaration spills into definition preview.** `restore_app`
   preview begins at 401 but extends through the next `restore` declaration
   at 404 and into its body. The parent has already assigned Opus a structural
   boundary fix and regression. This review has not verified that fix.
4. **File coverage wording is misleading.** On unindexed root `README.md`,
   lower header says “No semantic index” although footer says Index Partial
   and real repository indexes are usable. Prefer “File not indexed” (or
   “No semantic data for this file”) when the repository has an index.

At narrow width the quiet “Preview · Return opens” hint truncates heavily;
keep a recognizable Return hint if possible. This is a minor design concern.
System SF/monospace hierarchy, restrained emphasis, dynamic neutral styling,
native lists/splitters, local-detail quietness, and stacked metadata otherwise
make a coherent professional macOS inspector. Acceptance is incomplete until
the two height/compression defects and preview boundary are repaired.

## Screenshot evidence

- [Reference preview with main source unchanged](/Users/tqbf/codebase/radiology/build/context-ui-review/initial/reference-preview.jpeg)
- [Reference Back to original input](/Users/tqbf/codebase/radiology/build/context-ui-review/initial/back-to-input.jpeg)
- [restore_app definition preview and adjacent spill](/Users/tqbf/codebase/radiology/build/context-ui-review/initial/restore-app-under-caret.jpeg)
- [Honest external Some state](/Users/tqbf/codebase/radiology/build/context-ui-review/initial/external-some.jpeg)
- [Multiline open and compressed upper signature](/Users/tqbf/codebase/radiology/build/context-ui-review/initial/multiline-open-caret.jpeg)
- [Approximately 220-point inspector](/Users/tqbf/codebase/radiology/build/context-ui-review/initial/narrow-context.jpeg)
- [Back after passive source scroll](/Users/tqbf/codebase/radiology/build/context-ui-review/initial/back-after-passive-scroll.jpeg)
- [Selected upper reference retained while lower changes](/Users/tqbf/codebase/radiology/build/context-ui-review/initial/upper-selection-retained.jpeg)
- [Taller upper region still lacks snippet](/Users/tqbf/codebase/radiology/build/context-ui-review/initial/taller-reference-region.jpeg)
- [read_observation real definition preview](/Users/tqbf/codebase/radiology/build/context-ui-review/initial/read-observation-preview.jpeg)
- [Definition activated with Return](/Users/tqbf/codebase/radiology/build/context-ui-review/initial/return-definition.jpeg)
- [Old data cleared for unindexed Markdown](/Users/tqbf/codebase/radiology/build/context-ui-review/initial/unindexed-file-reset.jpeg)

## Exact limitations and remaining manual checks

Native attachment initially worked. One splitter-drag attempt returned
`Computer Use server error -10005: noWindowsAvailable`; the single immediate
bundle-ID state retry succeeded, and normal UI interactions subsequently
worked. No permission changes, custom automation/probes, or repeated app
restarts were used. One screenshot-emission expression initially referenced
an uninitialized `fs`; importing the documented module corrected capture
without app/tool restart. There is no unresolved attachment blocker.

Not verified: Cmd-click modifier/pointer combination; contextual activation of
an unselected row; repository replacement; no-index/stale transitions;
async stale publication races; internal no-refetch/cache counters; full
history-stack equality; copied clipboard bytes; VoiceOver speech; dark mode;
font-size changes; large reference-list scroll retention. The Unicode comment
at line 4286 was traversed in the real buffer and navigation to the following
call worked, but its em dash was beyond the visible horizontal viewport, so
this is not visual verification of that glyph. Exact Back evidence consists
of actual line/token restoration; no hidden byte-offset probe was used.

Targeted recheck/manual steps for the parent:

1. At `app.rs:1343`, click `open`; screenshot upper/lower signatures at 220
   points. Select reference 763, then change caret among args/executor_id.
   Screenshot visible call-site code and retained selection. Repeat with the
   upper split reduced and enlarged; list and preview must both remain usable.
2. At `runtime.rs:145`, select `restore_app`; screenshot preview restricted to
   401–403. Click definition or focus lower/Return; Back restores exact token.
3. At `app_image.rs:94`, select input, scroll source away, preview refs 413,
   420, 424 with Up/Down, commit with Return and Back. Cmd-click section at420
   should reach93 and Back restore the departure. Context-menu another row
   while one is selected should commit the clicked row, not the old selection.
4. For long-list retention, caret within `app.rs` impl HarnessApp at802–803,
   scroll its 92-reference/23-file list, then move within the same declaration
   among semantic tokens without changing upper identity. Capture before/after.
5. Open README.md, then a repository without SCIP coverage; screenshot cleared
   Context and honest availability labels. Do not modify tkos to manufacture
   stale state. Model tests remain the separate evidence for stale/race cases.

Only this review document is owned by the reviewer. Parent should link it from
PLAN/PROGRESS after reconciling its own documentation edits.

## Source-reader Return refinement — 13:45 build, 2026-10-04

Parent reported 125 tests / 20 suites and successful signing/resource gates;
no builds/tests were run by this reviewer. Terminated only Radiology PID70705,
launched the freshly packaged app on untouched tkos `app_image.rs`, and made
one native bundle-ID attachment attempt. AX and screenshots worked; no
recovery, retries, probes, permission changes, or tooling workarounds were
needed. Normal state captures continued throughout the focused check.

Observed outcomes:

- Clicked inside `section` at `app_image.rs:420` with source-reader focus,
  passively scrolled source two pages upward, then pressed Return. The source
  navigated to definition93. Cmd-[ restored line420 and the original section
  token/context. This was source-focused Return, not a sidebar activation.
- Double-click selected native word `section` (AX explicitly reported selected
  text), then Return navigated to93; Back returned to420. Pins created by the
  double-click persisted as expected.
- After Back, Right was used to collapse/advance the selection to its trailing
  boundary; Return again navigated to93 and Back returned420. This exercised
  the token-end path without a byte-offset probe. Exact placement immediately
  before `(` is not independently proven by screenshot/AX, so treat the
  specified byte-boundary case as partially verified.
- At `runtime.rs:145`, clicked `restore_app` in the source and pressed Return:
  navigated across files to `app_image.rs:401`; Back restored runtime145 and
  the original token/context. AX explicitly showed source-reader focus before
  activation. The bounded preview still contained401–403.
- Explicit Find References on restore_app, selected reference runtime276,
  then pressed Return with the reference list focused: navigated to276,
  **not** definition401. Back returned145. Source Return did not steal the
  existing sidebar Return action.
- Clicked external `Some` at runtime145 and pressed Return: no navigation or
  AX-tree change occurred, and its honest core/outside-repository state
  remained. Value/as_object and modified Return were not exercised.

No new product defect was observed. Back evidence is actual file/line/token
restoration, not instrumented history equality or hidden byte-offset proof.
No README recheck or old coverage gaps were expanded in this task.

Actual native captures are preserved in `build/context-ui-review/return-key/`
(removed by `make clean`):

- [Original section call](/Users/tqbf/codebase/radiology/build/context-ui-review/return-key/section-origin.jpeg)
- [Passive scroll before source Return](/Users/tqbf/codebase/radiology/build/context-ui-review/return-key/section-scrolled.jpeg)
- [Source Return reaches definition93](/Users/tqbf/codebase/radiology/build/context-ui-review/return-key/section-definition.jpeg)
- [Back restores section420](/Users/tqbf/codebase/radiology/build/context-ui-review/return-key/section-back.jpeg)
- [Native word selection Back](/Users/tqbf/codebase/radiology/build/context-ui-review/return-key/word-selection-back.jpeg)
- [Token-end attempt before Return](/Users/tqbf/codebase/radiology/build/context-ui-review/return-key/token-end-before-return.jpeg)
- [Token-end attempt Back](/Users/tqbf/codebase/radiology/build/context-ui-review/return-key/token-end-back.jpeg)
- [Cross-file source Return](/Users/tqbf/codebase/radiology/build/context-ui-review/return-key/restore-app-definition.jpeg)
- [Cross-file Back](/Users/tqbf/codebase/radiology/build/context-ui-review/return-key/restore-app-back.jpeg)
- [Sidebar reference preview](/Users/tqbf/codebase/radiology/build/context-ui-review/return-key/sidebar-preview.jpeg)
- [Sidebar Return commits276](/Users/tqbf/codebase/radiology/build/context-ui-review/return-key/sidebar-return276.jpeg)
- [External Return leaves source in place](/Users/tqbf/codebase/radiology/build/context-ui-review/return-key/external-return-no-jump.jpeg)

## Compact defaults — 13:56 build, 2026-10-04

Parent reported 126 tests / 20 suites plus check/build/signing/resource gates.
Those are separate evidence; this reviewer ran no source edits, builds, or
tests. Terminated only the prior Radiology PID23266, launched the new signed
app on untouched tkos `engine/rust/src/app_image.rs`, and attached once with
native computer-use by bundle ID. Initial AX showed the fresh Opening
repository state. A subsequent Go to Line sheet correctly showed1–500.

**Blocked before compact UI verification.** During the sequence setting
line94, pressing Return, reading state, clicking the source `input` position,
and reading state, native tooling returned exactly:

`Computer Use server error -10005: noWindowsAvailable`

The returned error does not identify which operation in that sequence failed;
some earlier actions may have executed. UI work stopped immediately with no
retry, restart, workaround, or diagnostics. No compact-build screenshot was
saved or inspected. The empty `/tmp/radiology-context-review/compact/`
directory was created for intended captures. There are no new screenshot links
to add. All prior evidence above belongs to earlier builds and must not be
treated as verification of compact behavior.

Design verdict for this build is **unverified**, not a product failure. No
observed layout or interaction defect can be reported from the available
evidence. The following manual checks are required, using the actual tkos
repository and native source reader; parent can save screenshots to
`build/context-ui-review/compact/`:

1. **Default scan:** Cmd-L94, click input. At280–360-point inspector width,
   capture one-row upper section icon/name/kind/line, definition93 and refs
   413/420/424 each as one row with disclosure, and one-row lower input under
   “Definition”. No literal “Under Caret” or automatic multiline preview.
   Repeat at220 points; names and locations must remain distinguishable.
2. **References:** Select413 then Down to420. Source must stay94 and rows stay
   collapsed. Right reveals numbered418–422 inline; Left hides them. Return
   commits420 and Cmd-[ returns the original input caret94. With420 selected,
   click424's chevron; it must expand424 without navigation or caret movement.
   Capture collapsed and expanded states with the unchanged source visible.
3. **Independent expansion:** Expand upper section and lower input. Arrow
   within input retains both expansions. Move to prefix on94: lower changes
   identity and collapses; upper section expansion stays. Capture before/after.
4. **Multiline opt-in:** Open `modules/agent/ffi/src/app.rs`, Cmd-L1343, click
   open. Upper defaults to one summary row. Expand it with sufficient region
   height and width; capture all seven signature lines1343–1349.
5. **Definition opt-in:** Open `engine/rust/src/runtime.rs`, Cmd-L145, click
   restore_app. Capture collapsed name/kind/location row, then expand and
   capture preview containing only app_image401–403. Location activation
   navigates401; Back returns the original runtime145 token. Briefly verify
   source-focused Return still does the same navigation.
6. **External facts:** Click Some on runtime145. Default row should identify
   core/package without prose bulk. Expand: honest outside-repository/no
   indexed-source state, no invented destination. Capture both states.

The reviewer changed only this chronological review section. PLAN, PROGRESS,
application source, build output, and tkos were not edited.

## Visible source caret — 14:08 build, 2026-10-04

Parent reported successful gates and129 tests /21 suites; this reviewer ran
no source edits, tests, or builds. Terminated only prior Radiology PID67793
and launched the new signed app on untouched tkos `app_image.rs`. The one
fresh native attachment worked, and all subsequent AX/capture interactions
worked without retries, workarounds, permission changes, or diagnostics.

Observed in light appearance at default source size:

- Cmd-L94 revealed a thin, character-height insertion bar at the start of the
  source line, distinct from the current-line wash. Clicking within input
  showed the bar at a character boundary within the occurrence tint. Left
  twice moved it; seven more Left presses moved into prefix. The lower compact
  row changed from input/local/93 to prefix/local/here, while upper section and
  its references stayed fixed. No navigation or source displacement occurred
  during the arrow sequence.
- Double-click prefix produced native word selection and pinned occurrences;
  the insertion bar was absent during the word selection. Single-click back
  within prefix restored the bar above its pinned/highlighted background.
  Clicking the upper reference420 transferred focus and hid the bar without
  moving the source from94. This uses pinned prefix rather than pinned input;
  both are actual symbols on the requested real source line.
- Cmd-L413, click within section, Right, then source-focused Return navigated
  to definition93. Cmd-[ returned to413 and the original token context; a
  subsequent Right moved the visible bar within section. Captures show the
  departure/restoration, but do not constitute a hidden byte-offset/history
  equality proof. The mouse pointer overlaps the token in some captures and
  makes that particular caret position less clear than the line94 examples.
- The latest compact UI is present: one-row declaration summary, collapsed
  chevron/line/source reference rows, lower “Definition” heading and one-row
  symbol/kind/location. No literal “Under Caret” appeared in the tested states.
  Full compact acceptance was not repeated.

Design verdict: the thin steady bar supplies a useful character-level cue
without dominating code. It remains distinguishable from the line wash and
occurrence backgrounds in the tested light appearance. No new product defect
was observed. This visual review does not establish exact1.5-point geometry,
85% opacity, timer absence, or all Unicode/fold boundary cases; those remain
implementation/model-test evidence. Dark mode, inactive-window gating,
range-selection gating, emoji/accents/tabs/EOF, and reference disclosure were
not exercised in this brief pass. Word-selection and sidebar-focus hiding
were exercised. Dataset, application code/builds, PLAN and PROGRESS untouched.

Actual native captures were saved in `/tmp/radiology-context-review/caret/`
and copied by the parent to `build/context-ui-review/caret/`. These links use
the preserved copies; `make clean` removes that build directory:

- [Input caret](/Users/tqbf/codebase/radiology/build/context-ui-review/caret/input-caret.jpeg)
- [Left movement within input](/Users/tqbf/codebase/radiology/build/context-ui-review/caret/input-left.jpeg)
- [Arrow movement to prefix and updated Definition row](/Users/tqbf/codebase/radiology/build/context-ui-review/caret/prefix-caret.jpeg)
- [Word selection hides insertion bar](/Users/tqbf/codebase/radiology/build/context-ui-review/caret/word-selection.jpeg)
- [Caret restored above pinned prefix tint](/Users/tqbf/codebase/radiology/build/context-ui-review/caret/pinned-prefix-caret.jpeg)
- [Sidebar focus hides caret](/Users/tqbf/codebase/radiology/build/context-ui-review/caret/sidebar-focus.jpeg)
- [Section departure before Return](/Users/tqbf/codebase/radiology/build/context-ui-review/caret/section-departure.jpeg)
- [Back to section413](/Users/tqbf/codebase/radiology/build/context-ui-review/caret/section-back.jpeg)
- [Right movement after Back](/Users/tqbf/codebase/radiology/build/context-ui-review/caret/back-right.jpeg)

## Current named-function shade — 15:02:16 build, 2026-10-04

Parent reported132 tests /22 suites, check/build/signing and empty-environment
packaged-resource gates. No tests/builds/source edits were performed by this
reviewer. Terminated only prior Radiology PID20573 and freshly launched the
signed app on untouched tkos `engine/rust/src/app_image.rs`. Native attachment
and subsequent captures worked; no recovery, retries, or tooling workarounds.

Observed in light appearance/default source size:

- Clicking input at94 shades the full visible source width of section from
  signature93 through **closing line101**. Blank102 and next function103 are
  excluded. The neutral wash is faint but identifiable when looking for it.
  Arrow movement toward prefix on the same line leaves the extent stable;
  current-line and symbol context respond independently without navigation.
- Double-click input pins its occurrences, then a single click on input at96
  restores an empty-selection caret. Pin outlines, occurrence fills, syntax,
  current-line wash, and thin caret remain legible above the function wash.
- Clicking blank102 clears the function wash while retaining pins and the
  separate current-line cue. Clicking sources103 transfers ownership; while
  folded, only its surviving signature line is shaded. Expanding its fold
  extends the shade through the revealed visible body instead of shading the
  unrelated following comment/type/container region.
- Adjacent restore_base398–400 and restore_app401–403 shade independently.
  Moving to restore_app and expanding it visibly shades401–403, excludes the
  preceding closing line400, and stops before restore404. No boundary spill.
- Passive upward scrolling three pages while the caret stays on restore_app
  moves the viewport to sources103–130. That visible unrelated function is
  unshaded; upper/lower context remain restore_app and footer remains401.
  Scrolling did not reassign shading to the viewport's function. An earlier
  one-page scroll gesture on sources caused no visible viewport displacement
  and is not counted as independent scroll evidence.
- Clicking the outside comment132 clears declaration context and shows the
  normal current-line cue without a function wash. No shading churn or text
  legibility defect was observed in the tested states.

Design verdict: successful, restrained whole-function emphasis in light mode.
The shade is sufficiently faint to stay behind syntax, pins, and caret while
still making the owning function's extent discoverable. No concrete defect
requiring Opus was observed. Exact3%/4.5% alpha and renderer mechanics are not
claimed from screenshots. Dark appearance, anonymous-closure ownership,
offscreen geometry stress, and a full impl/module exclusion matrix were not
exercised; this remained the requested short pass. Only this document and
native screenshot artifacts were written, leaving tkos/PLAN/PROGRESS untouched.

Actual captures were saved in `/tmp/radiology-context-review/function-shade/`
and copied by the parent to `build/context-ui-review/function-shade/`. These
links use the preserved copies; `make clean` removes that build directory:

- [Section93–101 extent with input caret](/Users/tqbf/codebase/radiology/build/context-ui-review/function-shade/section-input.jpeg)
- [Same-function arrow movement](/Users/tqbf/codebase/radiology/build/context-ui-review/function-shade/section-prefix.jpeg)
- [Pin/current-line/caret layering](/Users/tqbf/codebase/radiology/build/context-ui-review/function-shade/pin-caret-layering.jpeg)
- [Whitespace102 clears shade](/Users/tqbf/codebase/radiology/build/context-ui-review/function-shade/whitespace102.jpeg)
- [Folded sources signature](/Users/tqbf/codebase/radiology/build/context-ui-review/function-shade/sources-folded.jpeg)
- [Expanded sources body](/Users/tqbf/codebase/radiology/build/context-ui-review/function-shade/sources-expanded.jpeg)
- [restore_base398–400](/Users/tqbf/codebase/radiology/build/context-ui-review/function-shade/restore-base.jpeg)
- [Adjacent restore_app401–403](/Users/tqbf/codebase/radiology/build/context-ui-review/function-shade/restore-app.jpeg)
- [Passive scroll does not shade unrelated sources](/Users/tqbf/codebase/radiology/build/context-ui-review/function-shade/adjacent-passive-scroll.jpeg)
- [Outside comment132](/Users/tqbf/codebase/radiology/build/context-ui-review/function-shade/outside-comment.jpeg)
