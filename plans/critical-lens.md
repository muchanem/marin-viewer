# Critical Lens

**Shortcut update, 2026-10-11:** source modes use ⌥⌘1 Normal / ⌥⌘2 Critical;
plain ⌘0…⌘9 now address the ordered bookmarks in the third Context pane.
Bookmarks behave identically in both modes. See [bookmarks.md](bookmarks.md).

Critical Lens is a **source projection** for skimming function calls. Only
parsed call-name tokens can retain full contrast: repository, system/platform,
FFI, user-critical, and unknown calls. Proven ordinary runtime calls and all
non-call source recede, including syntax, strings/constants, declarations,
types, locals, receivers, and fields. This aggressive rendering supersedes
the original protect-all-syntax design. The source is never rewritten,
reflowed, or re-laid out. Normal mode is untouched.

This document is the upfront system design for the whole milestone and the
record of what each stage delivered. Stage one (classification, overrides,
Critical source rendering) was gated on 2026-10-04 and verified live by GPT
Sol (`plans/critical-lens-ui-review.md`). Stages two and three (function
summaries, bounded frontier, hover popover,
source gutter counts; sidebar lens depiction subsequently removed) are **implemented and gated** on this machine
(2026-10-04 16:19:59: `make check`, 161 tests in 32 suites, signed build,
strict codesign, packaged resource verification with the new `calls` query
role). Sol's final live check was blocked by native attachment error
`-10005: cgWindowNotFound`; the single permitted recovery failed too. UI
work stopped as requested. Implementation and model/build gates are complete,
but final summaries, hover, and counts remain visually unverified. The exact
manual checks and screenshot requests are in `plans/critical-lens-ui-review.md`.
Sections 5 and 6 below record the implemented
contracts; section 7 the tests; section 8 the limits. Fable 5.1 owns design, coding, model tests, and signed
builds; GPT Sol owns live UI inspection and may fix what it finds. The
implementer never launched the app. Sol's observations belong in
`plans/critical-lens-ui-review.md` (Sol's file; not edited here).

The latest rendering refinement was implemented and verified in light mode
by GPT Sol on the signed **16:53:36** build: **163 tests in 32 suites**, compile,
bundle, strict signing, and empty-environment resources pass. The user accepted
the new contrast (“this is much better”). Native captures also show concise
automatic upper call names and the independent lower Definition. Full frontier,
hover navigation, folded-count semantics, fresh mark toggles, and dark mode
remain unverified in that pass; the earlier failed attachment is historical.
See section 4 for the current rendering contract and the review for evidence.

### Latest sidebar simplification

The subsequent user request removed lens-specific sidebar depiction entirely.
Source modes share declaration/references plus Definition/outline; no sidebar
summaries or density counts remain. Hover and source gutter counts survive.
Gates pass with **164 tests / 32 suites** and signed build **17:05:05**.
No native relaunch was attempted while the user browsed the shared reader;
see the chronological review for honest evidence and limits. Earlier sidebar
milestone acceptance descriptions are historical and superseded.

### Hover interaction repair

Navigable names and full popup rows are now Buttons, not passive text with
narrow trailing links. Stable observable hosting and native full-popover
tracking preserve loading updates; a source-to-popup transit region suppresses
replacement by intervening tokens, with 700ms exit grace. External/missing
entries stay unavailable. Existing exact-caret navigation remains. Gates pass
with **166 tests / 33 suites**, signed **17:21:39**. Native physical click
acceptance remains blocked by fresh-instance selection; the review records
that exact limitation and manual steps. This does not restore sidebar lens
summaries or outline counts.

## 1. What the index and the parser actually provide

Measured on 2026-10-04 against the read-only app-owned tkos cache
(`~/Library/Caches/Radiology/repositories/98b359c61dd73dfb`, 13 rust-analyzer
1.97.1 strategies) with the opt-in `CriticalRealDataProbe`
(`RADIOLOGY_CONTEXT_PROBE=<cache dir> swift test --filter CriticalRealDataProbe`).
tkos was not modified.

| Fact | Measured | Consequence |
| --- | --- | --- |
| `SymbolInformation.relationships` | **0** across 56,389 symbol records | rust-analyzer emits no `is_reference` / `is_implementation` / `is_definition` edges. There are no SCIP call edges to use. Call edges must come from Tree-sitter call sites resolved to SCIP occurrences. |
| `Occurrence.enclosing_range` | set on 174,150 of 403,093 occurrences; on definitions it spans the whole item (`section` at app_image.rs:93 → enclosing 93–101) and on locals the `let` line | Function body extents are available **from SCIP** for every indexed definition, in every file, without parsing. Reference occurrences also carry one (277 of 427 in app_image.rs), but it is not a call edge. |
| `SymbolInformation.enclosing_symbol` | set on 40,492 records; every local names its enclosing callable (`local 6` → `app_image/section().`) | The enclosing callable of a *local* is known from SCIP; references to non-locals do not record their enclosing callable, so a call site's owner comes from containment (Tree-sitter for the open file, SCIP enclosing ranges elsewhere). |
| `symbol_roles` | only 0 and 1 (Definition) | No Import/Read/Write roles from rust-analyzer; nothing to filter on beyond definition. |
| External symbol information | 94 records (librespot-protocol, libsqlite3-sys) | Symbols from `core`, `alloc`, `std`, `serde_json`, `tokio`, `libc`, … have **no** kind, signature, or documentation. Their only metadata is the symbol string: scheme, package, version, descriptors. |
| Package naming | `rust-analyzer cargo core . …`, `rust-analyzer cargo std https://github.com/rust-lang/rust/library/std os/fd/…`, `rust-analyzer cargo libc 0.2.189 flock().`, `rust-analyzer cargo harness-ffi 0.1.0 …` | Package *name* is field 3; the version field may be `.`, a semver, or a URL. Overrides and profiles key on the name only. |
| Descriptor suffixes | `().` method/function, `#` type, `.` term, `/` namespace, `!` macro, `[…]` type parameter | Callable-ness of an external symbol is readable from its descriptor without spelling heuristics. |
| Operators and punctuation | `+`, `!=`, `[`, `]`, `..`, `?`, `*`, `|`, and even the surrounding spaces are occurrences of `core ops/…` trait methods | Those occurrences are runtime plumbing by identity but must never be dimmed: they are control flow and delimiters. Rendering dims identifier-shaped occurrences only. |
| FFI signatures | 222 in-repository signatures contain `extern` (`unsafe extern "C" fn save(...)`, `pub extern "system" fn Java_inc_tk_os_engine_NativeRuntime_run(`, extern-block declarations such as `v8__V8__IsSandboxEnabled()`) | FFI evidence exists in **indexed metadata** for repository items. For external FFI (`libc::flock`) the evidence is package ownership. |
| Coverage | engine/rust is `sourceOnlyNoDeps`: `serde_json::from_slice`, `Sha256::digest`, `.as_slice()` have **no occurrence** at all in app_image.rs; in harness-ffi (full workspace) `Value::as_object` resolves to `serde_json 1.0.151` | Absence of an occurrence is "unknown", not "ordinary". Counts and frontiers must say when coverage is partial. |
| Tree-sitter (Rust) | `call_expression` (function: identifier, scoped_identifier, field_expression), `generic_function`, `macro_invocation`, `await_expression`, `try_expression`, `unsafe_block`, `closure_expression`, nested `function_item` | Call sites, closures, and nested functions are all distinguishable nodes. Current queries already capture `function_item`/`closure_expression` as scopes and folds. |

## 2. Architecture

```
SemanticIndex (immutable)            SyntaxSnapshot (per open file)
        │                                     │
        ▼                                     │
CriticalityPolicy ──────┐                     │
  built-in profiles     │                     │
  + CriticalityOverrides│ (per repository,    │
    (persisted)         │  user wins)         │
        │               ▼                     ▼
        │       CriticalityWorker (actor)  ── classification cache keyed by
        │         classify(symbol) ─────────  (index revision, policy revision)
        │         projection(document) ─────  SourceProjection cache keyed by
        │                                     (path, bytes, document rev, policy rev)
        ▼
CriticalLensModel (@Observable @MainActor)
  mode: SourceMode (normal | critical)
  projection: SourceProjection?           ← generation-guarded publication
  overrides, policyRevision, repository root
        │
        ▼
SourceViewer / SourceViewerCoordinator
  receded UTF-16 ranges (sorted, disjoint)
  NSLayoutManagerDelegate.shouldUseTemporaryAttributes ← draw-time foreground only
```

### Boundaries

- **`SourceMode`** (`Critical/SourceMode.swift`) is a general presentation
  mode enum: `normal`, `critical`. Later modes (Structure, Changes, Effects,
  Authority) add cases; nothing in the base source model or renderer knows
  what a mode means.
- **`SourceProjection`** (`Critical/SourceProjection.swift`) is the general
  renderer contract: a value for one exact buffer (`path` plus
  `SourceContentIdentity`) carrying sorted, disjoint canonical byte ranges to
  recede. A mode produces a projection; the viewer applies one. The viewer
  never sees `Criticality`.
- **Classification** (`Criticality`, `CriticalityPolicy`, `CriticalityProfiles`)
  is pure and index-keyed. It never reads source text.
- **Overrides** (`CriticalityOverrides`, `CriticalityOverrideStore`) are a
  Codable value plus an actor that reads and writes one JSON file per
  repository under Application Support.
- **`CriticalityWorker`** is the off-main cache. Classification results are
  memoized per `SemanticSymbolID` and dropped when the index object or the
  policy revision changes; document projections are memoized by path, bytes,
  document revision, and policy revision.
- **`CriticalLensModel`** is the main-actor owner of mode, overrides, and
  the published projection. It is updated through `AppModel.refreshContext()`
  with the same inputs as the Context inspector, and it writes observable
  state only on change.

## 3. Classification

`Criticality` is `critical`, `ordinary`, or `unknown`. Every classification
carries a `Reason` so the UI can say why. Decisions are keyed by SCIP
`SemanticSymbolID` (identity), package ownership, and indexed metadata.
Spelling of the identifier is never consulted.

### Precedence (first match wins; deterministic)

| # | Evidence | Result · reason |
| --- | --- | --- |
| 1 | Symbol override for this exact symbol string | user choice · `symbolOverride` |
| 2 | Package override for the symbol's package name | user choice · `packageOverride` |
| 3 | `local N` symbol (parameters, locals, type parameters) | `unknown` · `local` — data, not an operation |
| 4 | Package is on the **explicit binding-package list** (`libc`, `jni`, `jni-sys`, `windows-sys`, `winapi`, `ndk-sys`, `core-foundation-sys`, `objc`, `objc2`, `block2`, `libsqlite3-sys`, `openssl-sys`, `libz-sys`, `bzip2-sys`, `zstd-sys`, `lzma-sys`, `curl-sys`, `libgit2-sys`, `libssh2-sys`, `ffmpeg-sys-next`, `v8`, `deno_core`); or descriptor path starts with `ffi/` in `core`/`std`, or `os/` in `std`. A `-sys` suffix alone is a naming convention, not ownership evidence: an unlisted `-sys` crate stays `unknown` | `critical` · `ffiPackage` |
| 5 | Indexed signature contains `extern "` (extern-block declarations and `extern "C"/"system"` definitions) | `critical` · `ffiSignature` |
| 6 | Package is a runtime package (`core`, `alloc`, `std`, `tokio`) **and** the descriptor path matches a **system-facing profile** (below) | `critical` · `systemAPI` |
| 7 | Symbol has an in-repository definition occurrence, or its package is one that defines symbols in this index (cfg-inactive items of a repository crate) | `critical` · `repositoryDefinition` |
| 8 | Package is `core`, `alloc`, or `std` | `ordinary` · `runtimePlumbing` |
| 9 | Anything else (third-party crates such as `serde_json`, `tokio` outside its system modules, unresolved) | `unknown` · `external` |

Rule 4 precedes 7 only to produce the more specific reason; both are
critical. Rule 6 precedes 8 so system-facing standard-library APIs stay
critical even though they live in a runtime package, as required.

### System-facing profile (rust-analyzer scheme)

Descriptor path prefixes (the part after the package header, before the
item) that are critical inside runtime packages:

- `std`: `fs/`, `net/`, `process/`, `env/`, `os/`, `thread/`, `io/` except
  the plumbing modules `io/error/`, `io/cursor/`, `io/buffered/`, `io/util/`,
  `io/impls/` (rust-analyzer descriptors follow the library's module files:
  `io/error/impl#[Error]last_os_error().`, `io/error/ErrorKind#WouldBlock#`,
  verified on tkos), `time/SystemTime`, `time/Instant`.
- `core`: only `ffi/` (through the FFI rule). Raw-pointer and `mem`
  helpers are language facilities, not platform boundaries, and are not
  promoted without boundary evidence.
- `alloc`: nothing (collections, strings, `Arc`, `format` are plumbing).
- `tokio`: `fs/`, `net/`, `process/`, `signal/` are critical; the rest of
  tokio is `unknown` (third-party), not ordinary.

Real tkos examples (from the probe, read-only):

| Occurrence | Symbol | Result |
| --- | --- | --- |
| `section(&mut input)?` in `restore` (app_image.rs:413) | `tk-js-runtime 0.1.0 app_image/section().` | critical · repositoryDefinition |
| `input.get(..4).ok_or(…)?` (app_image.rs:94) | `core slice/…get().`, `core option/Option#ok_or().` | ordinary · runtimePlumbing (`?` and `..` are operator occurrences and are never dimmed) |
| `libc::flock(file.as_raw_fd(), …)` (store_owner.rs:48) | `libc 0.2.189 flock()`, `std os/fd/raw/…as_raw_fd().` | critical · ffiPackage (both) |
| `std::io::Error::last_os_error()` (store_owner.rs:49) | `std io/error/impl#[Error]last_os_error().` | ordinary · runtimePlumbing (`io/error/` is an excluded plumbing module) — a user who disagrees marks the symbol critical |
| `OpenOptions…open(PathBuf::from(lock_path))` (store_owner.rs:41) | `std fs/OpenOptions#open().` | critical · systemAPI |
| `Value::as_object` (app.rs:1352) | `serde_json 1.0.151 value/Value#as_object().` | unknown · external |
| `self.transcripts.session(id.clone())` inside a closure (app.rs:1372) | `harness-ffi 0.1.0 …session().`, `alloc …clone().` | critical · repositoryDefinition; ordinary · runtimePlumbing (classification is per symbol; closure ownership matters only to stage two's call attribution) |
| `serde_json::from_slice`, `Sha256::digest` in engine/rust | no occurrence (dependency unresolved under `--no-deps`) | unknown by absence; nothing is dimmed |
| `Java_inc_tk_os_engine_NativeRuntime_run` (runtime.rs) | signature `pub extern "system" fn …` | critical · ffiSignature |
| `self`, `input`, `prefix` | `local N` | unknown · local |

Other indexer schemes (scip-go, scip-typescript, scip-python, scip-clang)
have no verified profile on this machine; their symbols classify by rules
1, 2, 3, 7, and 9 only. That is honest: nothing is dimmed for them until a
profile is verified against a real index.

### Overrides

- `Mark “name” ▸ Critical / Non-Critical / Built-In` and
  `Mark Package “pkg” ▸ Critical / Non-Critical / Built-In` in the source
  context menu, for the SCIP symbol under the pointer. Radio state shows
  the active choice; the Built-In item also names the built-in result
  ("Built-In (Ordinary)"). Locals have no override menu.
- Precedence: symbol override beats package override beats built-in
  policy. More specific wins; this is the only rule that lets a user keep
  `std` non-critical while promoting `std::fs::write`, or demote one noisy
  repository helper without touching its crate.
- Persistence: `~/Library/Application Support/Radiology/overrides/<repo-id>.json`,
  where `<repo-id>` is the same SHA-256 prefix of the canonical root path
  that `IndexCache.repositoryID` uses. Atomic writes; a corrupt or missing
  file is an empty override set. Different repositories cannot see each
  other's decisions. The viewed repository is never written.
- Format: `{"formatVersion":1,"repositoryRoot":"…","symbols":{"<symbol string>":"critical"},"packages":{"rust-analyzer cargo std":"ordinary"}}`.
  Package keys are `scheme manager name` without the version: a version
  bump keeps the decision, and equally named packages from different
  indexers in one repository (a Rust `uuid` crate and an npm `uuid`) cannot
  collide. The menu shows the bare name.
- `local N` symbols are never stored or offered in the menu. Their numbers
  are document-scoped and renumbered by reindexing after edits, so a saved
  `local 3` could silently attach to a different binding; the conservative
  choice is no persistent local marking at all, with no spelling-based
  remapping.
- Every change bumps `policyRevision`, invalidates the classification and
  projection caches, and recomputes the open file's projection.

## 4. Critical rendering (call-focused; supersedes stage-one syntax protection)

The user's follow-up explicitly superseded preserving keywords, literals,
constants, declarations and unknown non-call identifiers at full contrast.
Critical now emphasizes **call-name tokens only**. Non-call source recedes:
control flow, punctuation/operators, strings/numbers/constants, types,
locals, `self`, receivers/fields, declaration signatures and comments.
Normal remains unchanged. This changes rendering only, not classification,
call edges, summaries or frontier traversal.

### Projection rules

`CriticalProjection.make` walks Tree-sitter `callSites` and retains only
valid named callee byte ranges whose resolved SCIP classification is not
ordinary. Critical repository/system/FFI/user-marked calls remain prominent.
Ordinary runtime calls recede. Unknown or unresolved syntactic call names
remain visible because syntax proves a call, **without inventing an identity
or graph edge**. A critical mark on a non-call field/type/constant cannot
promote it. Declaration names and pattern constructors are not call sites.
Macro names qualify where the calls query captures them; their opaque
arguments do not produce invented calls. Unsupported dynamic callee shapes
have no named token to promote.

Sorted/merged prominent ranges are complemented over the exact source bytes
to yield generic `SourceProjection.recededByteRanges`. Unicode byte offsets
are converted only at the existing TextKit boundary. A missing index/document
can still render syntactic calls as unknown; missing or unsupported call
syntax yields no projection until real syntax is available. No source text,
layout, selection, navigation or history is changed.

### Drawing mechanism

The coordinator already serves as `NSLayoutManagerDelegate` for folds. It
now also implements
`layoutManager(_:shouldUseTemporaryAttributes:forDrawingToScreen:atCharacterIndex:effectiveRange:)`.
At draw time, for a character inside a receded range, it returns the
incoming temporary attributes (the ⌘-hover underline survives) plus a
`foregroundColor` equal to the **text storage's own color at that
character** with reduced alpha. The role therefore is always the current
syntax color: when Tree-sitter highlights arrive late and `SourceViewer`
rebuilds the attributed string, the next draw reads the new color. Light
and dark appearances resolve naturally because the base color is a dynamic
system color and `withAlphaComponent` keeps it dynamic.

Consequences:

- No text-storage mutation, no layout invalidation, no glyph regeneration.
  Toggling the mode is "replace a sorted range array, redraw the visible
  rect". Caret movement touches nothing.
- Canonical UTF-8 and UTF-16 coordinates, copy, Find, selection, pins, the
  current-function shade, the caret, folds, history, scroll, and the
  destination flash are untouched. Folded glyphs are null and never drawn.
- Composition: the receded array is cleared on source replacement and only
  reinstalled when the projection matches the buffer's bytes; a projection
  for an old index or old file can never decorate the new one. Index
  replacement bumps the document revision, which recomputes the projection;
  a missing index leaves named syntactic calls unknown; missing call syntax
  yields no projection.
- Range lookups are binary searches over sorted disjoint UTF-16 ranges,
  the same shape as the fold membership test, so a 4,880-line file with
  thousands of receded tokens costs one search per drawn run.

### Appearance

`Theme.recededSourceAlpha(appearance:)` is 0.30 in light mode and 0.38 in
dark mode for the aggressive call-focused pass. These are inspection-level
context rather than the primary reading foreground; Normal restores full
syntax contrast instantly. Dark mode uses more opacity to retain context.
See the chronological UI review for actual visual evidence and limits.
Weight is never changed: de-emphasis is opacity only (macOS typography
guidance), and a weight change would alter nothing legibly in SF Mono
while forcing layout. Only critical and unknown **call-name tokens** stay at full contrast; the critical/unknown distinction surfaces in hover and gutter rather than as a third text level, because a
three-level text ramp inside code hurts comprehension more than it helps.

### Mode control

- Toolbar: a segmented `Picker` ("Normal", "Critical") in the principal
  placement, disabled without an open file. Segmented controls are the
  native view-switch idiom (Finder, Xcode).
- View menu: "Source Mode" radio items, ⌥⌘1 Normal and ⌥⌘2 Critical, the
  Finder "View as" convention. Neither shortcut was previously bound.
- The mode is per session and not persisted (a lens, not a preference);
  revisit if the user asks.
- The footer gains no new element; the status of the projection is
  implicit (no data, no change).

## 5. Stage two: function summaries and the call graph (implemented)

Files: `Queries/*/calls.scm`, `Syntax/SyntaxQueries.swift` (`calls` role),
`Syntax/SyntaxSnapshot+Calls.swift`, `Critical/CallGraph.swift`,
`Critical/CriticalFrontierBuilder.swift`, `Critical/CallGraphWorker.swift`,
`Critical/CriticalSummaryModel.swift`, `UI/CriticalCallsContent.swift`,
`UI/CriticalCallRow.swift`, `UI/CriticalFrontierView.swift`.

### Call sites (syntax)

Every grammar ships a `calls.scm`. Named shapes capture `@call.name` (the
callee token) and `@call`/`@call.macro`; a fallback `@call.any` over every
call node keeps sites the named patterns do not describe (`(f)(x)`,
computed callees) as `dynamic` sites with no name. Comments and strings are
parser leaves, so nothing inside them is a site. Rust macro arguments are
token trees: calls inside `println!(…)` are not sites; the macro is. The
`SyntaxSnapshot.supportsCallSites` flag distinguishes "none" from
"unsupported".

### Call edges

Because rust-analyzer emits no relationships, every edge is: a Tree-sitter
call site **resolved** to the SCIP occurrence at the callee name, with the
callee identity being that occurrence's `SemanticSymbolID`. Accepted site
shapes for Rust: `call_expression` whose `function` is an `identifier`,
`scoped_identifier`, `field_expression` (method call), or
`generic_function`; `macro_invocation`; `await_expression` contributes no
edge of its own (the awaited call already does). Textual name matching is
never an edge. A site whose name has no occurrence is reported as an
unresolved site (counted, not guessed).

**Ownership of a call site.** A site belongs to the innermost
*callable node* that contains it: a named `function_item`, or a
`closure_expression`. Closures and nested named functions are their own
nodes in the summary, never flattened into the enclosing named function:

- A site directly inside the named function's own body (not inside any
  nested closure or function) is a **direct call** of that function.
- A site inside a closure is a direct call **of the closure**. The outer
  function's summary lists the closure as a conditional node ("closure at
  line N: k critical") and never counts its calls as unconditional direct
  edges, because whether and when the closure runs is unknown (it may be
  stored, passed, or never called). The same applies to nested
  `function_item`s. This is deliberately distinct from the
  current-function **shade**, which assigns a closure's lines to its named
  function for display only; shade ownership establishes nothing about
  execution.
- Frontier traversal through a closure is allowed only when the closure is
  the callee of a resolved edge, which Rust syntax never produces for an
  anonymous closure. So closures appear as leaf nodes with their own
  counts and an explicit "conditional" status.

**Enclosing callable in other files** (frontier expansion) uses the SCIP
definition occurrence's `enclosing_range` to bound the callee body, then
parses that file off-main (`SyntaxWorker`, cached by content identity as
`SemanticQueryWorker` already does for previews) to extract call sites.
Files whose parse fails or whose grammar is missing yield "no syntax" for
that node. External symbols with no definition yield "no body".

### Frontier

`CriticalFrontier.compute(callable:, depth:, nodeLimit:)` returns
`[CriticalPath]`: each path is the callee's identity plus the via chain of
*ordinary* intermediaries (`foo → normalize → HashMap::get → validate`
collapses to `validate via normalize`). Rules: a critical callee is
emitted and optionally traversed one level for nested display; an
ordinary callee with a body is recursed transparently; an unknown callee
is emitted as unknown and **not** traversed (unknown is never treated as
ordinary to find more). Cycles, including self-recursion, are cut by a
visited set; depth and node limits produce an explicit `truncated` flag.
Order is stable: source order of the first site, then path length. The
reachable critical count is the size of the union of direct critical
callees and frontier callees, so a symbol reached twice counts once.

### Counts and statuses (as implemented)

`CallCoverage` is `complete`, `partial(CallCoverageGaps)`, or
`noBody(reason)`. Gaps: unresolved sites (no SCIP occurrence at the callee
name, including dynamic sites), macro sites (expansion unknown), missing
bodies (an ordinary callee with a repository definition whose body could
not be read, parsed, or found; abstract declarations count here),
truncation (depth 4 / 48 bodies), parse errors in a traversed file,
**unknown callees** (unclassified; they may hide critical behavior), and
**conditional sites** (inside closures or nested named functions, where
execution is unproven). Any gap makes the result partial, so a function
whose only calls are unknown or closure-owned is a lower bound, never a
proven zero. `noBody` reasons: external, abstract, no syntax, unreadable,
not indexed, unsupported language (no `calls` query).

`CountAnnotation` is the generic presentation value for the gutter and
source gutter: `3` (proven), `3+` (partial, at least), `–` (no body). Proven zero
recedes; partial and no-body are visibly distinct. Status lines read
"3 direct · 7 reachable · 2 conditional · partial" with the full honest
sentence in the tooltip and accessibility label.

### Worker caching and concurrency (as implemented)

`CallGraphWorker` is an actor configured with (root, index object, index
revision, policy, policy revision). An effective `configure` empties every
cache and advances a **work epoch**; so does an effective byte
invalidation in `prime` (the viewer's current buffer, structure, and
occurrences for the open file) and a same-bytes upgrade that adds
structure or occurrences (no-body answers for that file are dropped).
Every operation captures the epoch it started under and never writes a
cache or continues a traversal after it changed; a disk load that finishes
after the same path was primed yields to the primed bytes. Frontiers are
keyed by (path, owner range, content identity) and all of them are dropped
when any file's bytes change, because a root in another file may have
traversed it. The summary model adds its own generation guards and keys
source gutter requests by file bytes, index, document and policy revisions;
hover requests by pointer dwell. The gutter sweep runs at utility priority and
yields between fold-bearing callables, publishing every six.

### Sidebar removal (current; supersedes the automatic Critical sections)

The user requested removing the lens depiction because it was not paying its
freight. The sidebar now behaves identically in Normal and Critical: enclosing
declaration/references plus Definition/outline, with concise existing rows,
disclosures and navigation. No upper Critical call/status/unknown/conditional
section, lower callable frontier, or outline density annotations remain. No
replacement summary was added.

`CriticalSummaryModel` owns only hover and source fold annotations. Its upper/
lower phases, identity keys, tasks, request counters and via disclosure state
were removed. Caret identity changes schedule no graph work. The utility sweep
visits only callables with source body folds; declarations that existed solely
for outline annotations schedule nothing. Hover loads its frontier on pointer
dwell and primes the current source bytes before traversal. Source gutter,
hover, classification, persistent marks and call-focused projection remain.
Unused sidebar view components and critical-list row dispatch were removed;
reference activation always uses the original reference path.

## 6. Source hover and gutter (outline counts removed)

- **Hover** (`CriticalSummaryModel.pointerMoved`, `ReaderTextView`
  popover, `UI/CriticalHoverView.swift`): in Critical mode the reader
  reports the byte under the pointer; a callable with a repository body,
  or a critical external callable, opens an `NSPopover` after a 350 ms
  dwell. Plumbing and locals never open one. The popover shows the name, a
  whole-row definition button (title and trailing Definition are both targets),
  or an honest unavailable external row, the status line, and up to 8
  single-line rows; the pointer may leave the token and enter the popover
  (a 700 ms grace, cancelled by native popover tracking). It closes when
  the pointer leaves both, on click, key, scroll, mode, file, index, or
  repository change, and when the system closes it (semitransient). Hover
  never moves the source, caret, selection, or history; row and link
  activation go through `navigate(toDefinition:)`, so Back returns to the
  exact caret. External rows have no destination and say so.
- **Fold gutter** (`LineNumberGutter.annotations`): in Critical mode a
  collapsed function's count lane shows the reachable critical count in a
  rounded square with an accent stroke instead of the neutral hidden-line
  capsule; proven zero and no-body are tertiary with a separator stroke;
  partial reads `n+`. The hidden-line count stays in the tooltip and
  accessibility text ("Collapsed function — 12 lines hidden · at least 3
  critical operations reachable, coverage partial"). Fold glyph handling
  and layout are untouched; the gutter only draws values it is given.
- **Sidebar outline:** ordinary callable rows sorted by descending source-line span, followed by non-callable hierarchy; lens
  counts were removed at the user’s request.

## 7. Validation and acceptance by stage

Stage one (gates passed 2026-10-04; see PROGRESS.md for the exact run):

- `CriticalityPolicyTests`: precedence table, package-name parsing (URL
  and `.` versions), system profile, `-sys` convention, extern signatures,
  locals, third-party unknown, symbol-over-package override, reset.
- `CriticalProjectionTests`: actual parsed calls stay prominent by identity,
  ordinary calls recede, non-call keywords/literals/fields/types/declarations
  recede even when marked critical, pattern names/comment/string spellings
  cannot become calls, unresolved call syntax stays visible without identities,
  Unicode byte/UTF-16 boundaries and exact-source matching remain correct.
  The older protect-all-syntax expectations are superseded.
- `CriticalityOverrideStoreTests`: round trip, isolation between
  repositories, corrupt file tolerance, location outside the repository.
- `CriticalLensModelTests` (through `AppModel`): mode toggle publishes and
  clears the projection without touching navigation, caret, or history;
  override changes recompute; caret moves do not; cached projections are
  reused across file revisits.
- `SourceProjectionDrawingTests`: the delegate returns the storage color
  at reduced alpha only inside receded ranges, keeps incoming hover
  attributes, respects effective-range bounds, does not change the text
  storage, selection, or folds, survives a fold, clears on source
  replacement, and is consulted by TextKit on every draw pass. TextKit
  honors temporary attributes only when drawing to the screen, so an
  offscreen bitmap cannot show the dimming (verified: even a directly added
  temporary color leaves offscreen pixels unchanged). The visual result is
  Sol's live check.
- `CriticalLensModelTests.editsBeforeLoadAreKeptAndSavesStayOrdered`: a
  decision made before the persisted file loads survives the load and is
  merged with untouched persisted decisions; rapid edits end with the last
  snapshot on disk; saves are chained and revision-guarded.
- `CriticalityOverrideStoreTests`: an older revision cannot overwrite a
  newer one; a deletion failure (read-only parent) is thrown, not
  swallowed.

Checks for GPT Sol are listed in PROGRESS.md.

Stages two and three (gates passed 2026-10-04 16:19:59; 161 tests in 32
suites):

- `CallSiteExtractionTests`: every fixture grammar yields named sites;
  Rust shapes, macros, closure/nested-function ownership, dynamic
  `(f)(x)` sites kept as unresolved, comments/strings excluded.
- `CriticalFrontierTests`: via paths, dedup across cycles, self-recursion
  and diamonds, distinct union count, unknown listed and partial, depth and
  body caps, missing/abstract bodies, proven zero only when complete,
  unknown-only and closure-only functions never proven zero.
- `CallGraphWorkerTests`: sites resolve to SCIP identities on the fixture
  index, bodies located across files, marks flow into frontiers,
  unresolved/dynamic sites partial, no-syntax and abstract no-body, changed
  same-length callee bytes invalidate summaries and dependent frontiers,
  reconfiguration and byte invalidation during an in-flight load never
  populate the current caches.
- `CriticalSummaryModelTests` (through `AppModel`): identities drive
  requests (caret moves inside one identity request nothing), Normal
  clears and Critical restores from cache, marks refresh, stale results
  are dropped when the mode or file changes, row activation navigates and
  Back returns, external rows report honestly, hover opens after the
  dwell and closes by grace or events without moving anything.
- Read-only tkos probe (`CriticalRealDataProbe`, opt-in): `restore_app`
  (app_image.rs:401) → direct critical `restore` only, complete. With
  `restore` marked ordinary in the probe's own policy (nothing persisted):
  `restore_app` → 0 direct · 2 reachable · partial, paths `section via
  restore` (three sites collapsed to one path) and `compatibility via
  restore`, gaps 6 unresolved (serde_json::from_slice, Sha256::digest and
  friends under `--no-deps`) and 2 macros. `restore`@404 itself: 2 direct
  (`section` ×3, `compatibility`), partial. `read_observation`
  (app.rs:2058): 1 direct (`observe_session`), complete.
  `publish_instructions` (app.rs:1157): 6 direct critical (`bad`,
  `publish`, `store`, `session_in_store`, `adopt_instructions`, `render`),
  7 conditional sites in closures, 5 unknown callees (`get`,
  `from_value`, `now`, `timestamp_millis`, `json!`), partial. `open`
  (app.rs:1343): 39 direct critical, 23 conditional sites, 9 unknown,
  8 macros, partial.

## 8. Known limitations and mitigations

- Calls inside macro arguments are not sites (token trees); the macro is
  reported and makes coverage partial.
- Trait-method calls resolve to the trait method's identity; its body is
  abstract (no body), so a frontier through a trait call is partial. No
  dispatch resolution is attempted.
- Dependency-degraded crates leave dependency calls unresolved; they are
  counted as gaps, never guessed.
- Closure and nested-function bodies are never traversed from the outer
  function; their site counts appear as a conditional line only.
- Only grammars with a `calls.scm` (all eight registered) report sites;
  Swift and Kotlin have no SCIP indexer, so their sites never resolve.
- Hover and popover behavior, gutter badges, and the sidebar layout were
  not visually verified by the implementer; Sol's pass decides.

- rust-analyzer provides no relationships, so trait-method calls resolve to
  the trait method symbol, not an implementation; the frontier follows the
  trait method's definition (an abstract body) and reports it as such.
- Dependency-degraded crates (engine/rust under `--no-deps`) leave calls
  into dependencies with no occurrence. They are neither dimmed nor
  counted; coverage says partial.
- Profiles exist only for the rust-analyzer scheme. Other schemes classify
  repository symbols as critical and everything else unknown until a
  profile is verified on a real index.
- `std::io::Error` and friends are deliberately plumbing; if a reader wants
  `last_os_error` critical, one override does it.
- Dimming is appearance-aware but was not visually verified by the
  implementer; Sol's pass decides the final alphas.
- Deferred by request: LLM classification, weights, automatic project
  inference, interprocedural dataflow, effects/authority/security, path
  sensitivity, virtual-dispatch perfection, and a rules language.
