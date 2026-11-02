# SCIP first cut: native UI handoff

> Historical checkpoint: this was written for the first Sol UI pass. Later
> tkos acceptance, occurrence/pinning, picker, folding, and performance work
> superseded several open items and validation statements. Read `PLAN.md`, the
> top of `PROGRESS.md`, and `plans/agent-handoff.md` for current state.

Audience: the GPT Sol agent doing native UI testing and refinement. The
architecture below is decided and implemented; keep it unless a proven defect
requires discussion. Read `plans/scip-semantic-navigation.md` first.

## What exists

- `SemanticIndexService` (actor) inspects the repository, selects indexer
  strategies, loads or generates `index.scip`, and publishes atomically.
- Adapters: rust-analyzer (verified end to end), scip-go, scip-typescript,
  scip-python (adapters and app-managed install implemented, not yet run on
  real projects), scip-clang (detect-and-run if installed).
- `SemanticModel` (main actor) holds status, outcomes, the open file's byte
  mapped occurrences, caret target, references, ⌘T matches.
- UI: footer `SemanticStatusView` with diagnostics popover; inspector segmented
  Outline / Symbol with `SemanticInspectorView`; `SymbolSearchSheet` on ⌘T;
  `ReaderTextView` ⌘-hover underline + pointing hand, ⌘-click, context menu
  items; Navigate menu Go to Definition (⌃⌘J) and Find References (⌃⌘R);
  Repository menu Reindex (⌃⌘I) and Cancel Indexing.

## Build, test, launch

```sh
cd /Users/agentzero/codebase/radiology
make check && make test && make build
build/Radiology.app/Contents/MacOS/Radiology --repository /tmp/agent-demo --file harness/crates/harness-core/src/lib.rs
```

Tool state on this machine (2026-10-03): rust-analyzer 1.98.1 installed as a
rustup component (`rustup component add rust-analyzer`), Go 1.26.2, Node
21.6.2, npm 7.0.15, Python 3.9.1 (scip-python needs 3.10+), protoc and the
`scip` CLI v0.10.0 at `/tmp/sciptools/scip` for cross-checking indexes
(`/tmp/sciptools/scip print --json index.scip`, `scip stats --from index.scip`).

## Fixtures and real repositories

| Path | What | Notes |
| --- | --- | --- |
| `Tests/RadiologyTests/Fixtures/scip-rust/` | Two-file Rust crate plus the rust-analyzer `index.scip` it produced | Hermetic decoder/resolution tests |
| `/tmp/demo-crate` | Git copy of that crate with no index | App generated `rust-analyzer.scip` in 2.6 s; relaunch reused the cache |
| `/tmp/agent-demo` | Git copy of `tkos/modules/agent` (`ffi` + `harness` workspaces, 222 Rust files) | The app generated both strategies: `ffi` 71/71 files in 39.5 s, `harness` 151/151 in 31.8 s (~3 GB RSS peak for rust-analyzer). Use this as the primary real-world target. |
| `/tmp/harness-demo` | Git copy of `harness` alone | Fails in `cargo metadata` (`../ffi` path dependency missing): a real Failed-state example with exit status and stderr in the popover |
| `/Users/agentzero/codebase/tkos` | The real monorepo | The packaged app completed all detected strategies. Rust coverage is 338/340 across 11 real Cargo project directories; engine is Partial/sourceOnlyNoDeps at 28/29 and includes `app_image.rs`. See the acceptance evidence below. |

Cache: `~/Library/Caches/Radiology/repositories/<16-hex-id>/` holds
`<strategy>.scip` and `index-metadata.json`. Delete the directory to force a
cold generation. Tools: `~/Library/Application Support/Radiology/tools/`.

Recreate the demos if `/tmp` was cleaned:

```sh
rm -rf /tmp/agent-demo && cp -R /Users/agentzero/codebase/tkos/modules/agent /tmp/agent-demo \
  && find /tmp/agent-demo -type d -name target -prune -exec rm -rf {} + \
  && cd /tmp/agent-demo && git init -q && git add -A && git -c user.email=t@e -c user.name=t commit -qm demo
rm -rf /tmp/demo-crate && cp -R /Users/agentzero/codebase/radiology/Tests/RadiologyTests/Fixtures/scip-rust /tmp/demo-crate \
  && rm /tmp/demo-crate/index.scip && cd /tmp/demo-crate && git init -q && git add -A && git -c user.email=t@e -c user.name=t commit -qm demo
```

## Workflows to verify natively

1. **Cold open → generate.** Delete the cache, open `/tmp/agent-demo`. Footer
   shows "Indexing…" with the rust-analyzer progress line in the popover, then
   "Index Current". Files remain browsable, outline and search work meanwhile.
2. **⌘-hover.** Hold ⌘ over an identifier with an in-repository definition:
   accent underline and pointing hand. Over `std`/external symbols, keywords,
   whitespace, folded text, or past end of line: nothing. Release ⌘: underline
   clears. Syntax colors, selection, folding and the gutter stay correct.
3. **⌘-click and exact Back.** Scroll away from the clicked line first. ⌘-click
   jumps across files with the transient accent highlight; the destination's
   folds open if needed. ⌘[ returns to the exact clicked byte and line; ⌘]
   goes forward again. A pinned outline anchor made before the click must
   still be in history.
4. **Keyboard and menu.** Place the caret on an identifier: Navigate > Go to
   Definition (⌃⌘J) and Find References (⌃⌘R); right-click shows "Go to
   Definition of “name”" and "Find References to “name”" with the former
   disabled on definitions and external symbols.
5. **References.** Inspector switches to Symbol; groups by file with line
   numbers, monospace line text, "definition" marker; clicking a row jumps
   exactly and records history.
6. **⌘T.** Exact > prefix > initials (`sbg`) > fuzzy; kind and path shown; Return
   navigates to the definition; empty/indexing/failed states have useful text.
7. **Symbol inspector.** Name, kind, canonical ID (selectable), definition
   location, reference count, index state; on a definition the card says
   "Defined here" and lists other definitions when there are several.
8. **Status, failure, cancel, reindex.** Rename `rust-analyzer` out of the way
   (or `rustup component remove rust-analyzer`) and Reindex: "Index Failed"
   with the reason and an **Install rust-analyzer** button; Install runs
   `rustup component add rust-analyzer` with progress and then indexes. Start
   a cold index of `/tmp/agent-demo` and Cancel Indexing: no `rust-analyzer`
   or `cargo` processes remain (`pgrep -fl 'rust-analyzer|cargo'`).
9. **Stale.** Touch a source file (`touch src/lib.rs`), press ⌘R: "Index
   Stale" shows immediately with the cached index still navigating, then
   regeneration brings it back to Current. Commit a change to see the HEAD
   reason.
10. **Mixed and unsupported.** Open the radiology repository itself: "No Index"
    with "Files here are Swift" (no SCIP indexer for Swift). Open a folder with
    `package.json` to see the scip-typescript strategy; without the tool the
    popover offers Install.
11. **Appearance and sizing.** Light/dark, ⌘+/⌘- at several sizes, Reduce
    Motion, VoiceOver labels on the status control, inspector rows, and ⌘T rows.

## Evidence from this cut

- A cold packaged-app run on the untouched real tkos repository produced real
  Cargo-identity Rust indexes for 338/340 files: engine 28/29, phone-provisioner
  1/1, agent ffi 71/71, agent harness 151/151, game 3/3, imap 3/3, mls 11/11,
  scene3d 3/3, spotify 5/5, storage 2/2, tkreplica 60/61. Engine reports the
  exact Cargo failure and sourceOnlyNoDeps limits; its missing
  `snapshot_profiles_test.rs` is an undeclared orphan. tkos stayed Git-clean.
- The generated real engine index contains 935 `app_image.rs` occurrences and
  152 definitions under `tk-js-runtime 0.1.0`. Product-code lookup of the
  `PreparedApp` use in `restore_app` finds one repository definition and 11
  references.

- `make check`, `make test` (76 tests in 14 suites), `make build` with ad-hoc
  signing pass; `codesign --verify --deep --strict` passes; the packaged
  `--verify-resources` run loads all 8 grammars.
- `IndexingTests/realRustAnalyzerGeneratesAnIndexFromScratch` runs the real
  tool on a temp copy of the fixture with no prebuilt data (2.1 s) and resolves
  `Circle` across files.
- The built app, launched on `/tmp/demo-crate`, wrote `rust-analyzer.scip`
  (4.5 KB, 2 documents) and `index-metadata.json` with HEAD
  `30b13d0c…`; a relaunch reused the cache without regenerating.
- The built app, launched on `/tmp/agent-demo`, ran two rust-analyzer
  strategies and cached `rust-analyzer_ffi.scip` (71 documents) and
  `rust-analyzer_harness.scip` (151 documents) with HEAD recorded.
- Decode + normalize of the two cached agent-demo files (28.8 MB, 222 docs,
  40k symbols) took 0.34 s + 0.42 s in a debug build; a ⌘T query 0.13 s. Watch
  for ⌘T typing latency on larger indexes (search runs off-main with a 60 ms
  debounce, but the list still repaints 200 rows).
- Cancellation test confirms the process group (shell plus background `sleep`)
  is gone after cancel.

## Known issues and unverified items

- Native CUA earlier exercised the semantic UI on `/tmp/demo-crate`: cross-file
  definition navigation and exact Back, references, Cmd-T focus/results,
  folded-target reveal, inspector layout, and destination highlight. During
  the final tkos build it repeatedly failed to attach with `cgWindowNotFound`
  even though Radiology was a running foreground app, so the final tkos
  status-popover and app-image pointer/keyboard sequence remain visually
  unverified. Headless product-code lookup verifies their semantic data.
- Hover uses `NSLayoutManager` temporary attributes; verify it never persists
  after a buffer or index swap (guards exist: `clearHover` on revision change).
- `flagsChanged` only fires when the text view is first responder; hovering
  with ⌘ held while another view has focus may not underline until the mouse
  moves. Decide whether that is acceptable.
- Multiple definitions: first is followed; the rest are rows in the Symbol
  pane. No chooser menu yet.
- At this first-cut checkpoint only rust-analyzer was proven end to end.
  Subsequent Sol work exercised Go and TypeScript paths; Python still required
  Python 3.10+ while this machine had 3.9, and scip-clang still required a
  compilation database plus manual binary installation. See current PROGRESS.
- `rust-analyzer` prints "Duplicate symbol" warnings on stderr for cfg
  variants; these are warnings, not failures, and appear in the popover only
  when a run fails.
- A pre-existing timing-sensitive test, `destinationHighlightRestartsAndClearsWithoutChangingText`,
  failed once under full-suite load before this work and passed in isolation
  and in later full runs.
