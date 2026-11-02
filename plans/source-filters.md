# Source filters: Hide Tests and Source Files Only

**Active-file reveal update, 2026-10-11:** Files now derives a current-document
exception, including through its text filter, so navigation can expand/select/
center it. Model filter data/preferences and other excluded files remain;
Changes retains its policy. Footer “current file revealed” supersedes the older
hidden-file notice below. See [files-sidebar-navigation.md](files-sidebar-navigation.md).

Status: designed and implemented by Opus 5.5 on 2026-10-04 (see PROGRESS.md for
actual gates). GPT Sol owns live UI acceptance in
[source-filters-ui-review.md](source-filters-ui-review.md); nothing here is a
claim of UI verification.

## User request

“add an option to hide test code (including rust marked test blocks, which occur
in the middle of normal source files) — support at least rust, kotlin, python
(best effort), ts. also: an option to filter the left sidebar file browse down to
just source code, not documentation, build artifacts, &c”.

## Options, location, persistence

Two independent options, both off by default:

| Option | Affects | Controls |
| --- | --- | --- |
| **Hide Tests** | Files tree and PR Changes (recognized test paths) and inline test regions inside ordinary source | View ▸ Hide Tests (⌃⌘T) |
| **Source Files Only** | Files tree and PR Changes | View ▸ Source Files Only (⌃⌘O) |

The 2026-10-08 user request makes these menu-only controls, removing toolbar and
navigator icons. View also offers Show All Files; footer names active filters
(`Source only`, `Tests hidden`) alongside visible/total counts. Native acceptance
is recorded in sidebar-refinement.md. Both remain
`SourceFilters` values on `AppModel`, persisted app-wide in the injected
`UserDefaults` (`hideTests`, `sourceFilesOnly`), like the recent-repositories
list. They are viewing preferences that a reader who wants them wants on every
repository. Source mode and text size remain session-only, as before. Toggling
never changes the repository, source mode, caret, history, pins, marks, folds or
source bytes.

## Scope (explicit)

- **Filtered:** Files tree/query and PR Changes rows use the same SourceFilters.includes
  policy. Changes retains original PR order; deleted files use their Before path.
  Renames/copies are included if either available Before or After path passes
  both active filters, so extension/source-set moves do not disappear.
- Changes displays visible-of-total file counts and visible text-file +/− totals
  (binary line counts unavailable), with filter controls in the View menu.
  Filtered-empty says No Changes to Show with Show All Files; genuinely empty
  says No Changed Files. Selection sync is restricted to visible rows; filtering
  never opens another file or changes the current revision/caret/history.
- **Not filtered:** ⌘K Go to File, repository Search, Go to
  Symbol, semantic navigation, indexing, and the repository model. These are
  explicit escapes to any file; a reader can always reach a filtered file. The
  full `RepositorySnapshot` is unchanged.
- The open file is never closed by filtering. When the open file is filtered
  out, the sidebar footer says so (“open file hidden by filters”).
- Files and Changes empty results show a native empty state with a “Show All Files” action that
  turns both options off.
- Directory expansion is explicit state keyed by relative path
  (`FileTreeExpansion`). Filtering, unfiltering and PR snapshot switches keep it.
  Order is the existing `FileNode.tree` order (directories first, Finder order).
  Empty directories are pruned because the tree is rebuilt from included files.

## Test path classification (`TestPathClassifier`)

Whole-path, component-exact rules; never substring (“contest”, “latest”,
“attestation”, “testing.py” are not tests).

- Directory components: `test`, `tests`, `Tests`, `__tests__`, `__mocks__`,
  `__fixtures__`, `testdata`, `test-support`, `test_support`, `testsupport`,
  `test-utils`, `test_utils`, `testutils`, `androidTest`, `testFixtures`, and
  Gradle/Kotlin source sets under `src/` whose name ends in `Test` (`jvmTest`,
  `commonTest`, `androidUnitTest`, `integrationTest`, …).
- File names: `*_test.go`; Rust `tests.rs`, `*_test.rs`, `*_tests.rs`; Python
  `test_*.py`, `*_test.py`, `tests.py`, `conftest.py`; any source extension with a
  `.test`/`.spec` stem suffix (`a.test.ts`, `a.spec.tsx`, `build.test.py`,
  `a.test-d.ts`); C/C++ `*_test.c[c|pp|xx]`, `*_unittest.*`.
- Not tests: `testing/`, `spec/`, `e2e/`, `bench/`, `fixtures/` (data used by
  production as well), Kotlin `src/main/**/FooTest.kt` (a production feature can
  be named that; only the source set decides).

## Source file classification (`SourceFileClassifier`)

A file is source when its extension is a code/header extension (Swift, Rust, Go,
Python, JS/TS family, Kotlin, Java, Scala, Groovy, C/C++/Objective-C headers and
sources, C#, F#, Ruby, PHP, Lua, Zig, Nim, Dart, Elixir, Erlang, Haskell, OCaml,
Clojure, Elm, Julia, R, Perl, shell, SQL, protobuf/Thrift/GraphQL IDL, Vue/Svelte/
Astro, assembly, CUDA/Metal/GLSL/HLSL/WGSL shaders) **and** none of these apply:

- A directory component is a build artifact, dependency or cache: `target`,
  `build`, `dist`, `out`, `.build`, `DerivedData`, `node_modules`, `vendor`,
  `Pods`, `Carthage`, `bower_components`, `jspm_packages`, `.gradle`, `.next`,
  `.nuxt`, `.svelte-kit`, `.turbo`, `.parcel-cache`, `.cache`, `coverage`,
  `__pycache__`, `.venv`, `venv`, `.tox`, `.mypy_cache`, `.pytest_cache`,
  `.ruff_cache`, `site-packages`, `.terraform`, `generated`, `__generated__`,
  or any hidden (dot) directory. (RepositoryWorker already drops some of these;
  the classifier does not rely on that.)
- The name marks generated output: `*.min.js`, `*.min.css`, `*.bundle.js`,
  `*.generated.*`, `*.g.dart`, `*.pb.go`, `*_pb2.py`, `*_pb2_grpc.py`,
  `*.pb.swift`.
- The name is a build manifest/config: `Package.swift`, `build.gradle(.kts)`,
  `settings.gradle(.kts)`, `setup.py`, `*.config.{js,ts,mjs,cjs,mts,cts}`, and
  dot-files.

Documentation (`.md`, `.rst`, `.txt`), data (`.json`, `.yaml`, `.toml`, `.lock`),
markup/styles (`.html`, `.css`), images and binaries are never source.

## Inline test regions (`TestRegionDetector`, Tree-sitter)

Runs inside `SyntaxWorker` on the same tree that produces highlights/folds; it
walks real node shapes (verified by dumping the pinned grammars, 2026-10-04),
never braces or strings. Output: `SyntaxSnapshot.testRegions` (sorted, disjoint,
outermost, half-open canonical byte ranges) and `isTestOnlyDocument`.

### Rust (`attribute_item` siblings before an item)

An item (`function_item`, `mod_item`, `impl_item`, `use_declaration`, `const_item`,
`struct_item`, `let_declaration` in blocks, …) is test-only when one of the outer
`attribute_item`s that precede it is:

- `#[cfg(P)]` where `P` is definitely false in a non-test build. `P` is parsed from
  the attribute's `token_tree` (identifiers, `key = "value"`, nested
  `all/any/not`) and evaluated in Kleene three-valued logic with `test = false`,
  `doctest = false`, every other predicate unknown. `cfg(test)`,
  `cfg(all(test, feature = "x"))` hide; `cfg(any(test, feature = "prod"))`,
  `cfg(not(test))`, `cfg_attr(test, …)` and unparseable shapes do not.
- a test attribute: path whose last segment is `test` (`test`, `tokio::test`,
  `async_std::test`, `sqlx::test`, `test_log::test`), or `rstest`, `test_case`,
  `wasm_bindgen_test`, `quickcheck`.

A `mod_item` whose body starts with `#![cfg(test)]` is test-only; a file whose
root starts with it is a test-only document. The region spans every preceding
attribute and comment back to the previous item, plus directly adjacent `///`/
`/** */` doc comments, through the item's end. `#[cfg(test)] mod x;` path
declarations are items too. Token trees (macro bodies) are not searched.

### Kotlin (`function_declaration`/`class_declaration` `modifiers` → `annotation`)

The annotation's `user_type` last `type_identifier` decides. Test functions:
`Test`, `ParameterizedTest`, `RepeatedTest`, `TestFactory`, `TestTemplate`,
`BeforeTest`, `AfterTest`, `BeforeEach`, `AfterEach`, `BeforeAll`, `AfterAll`.
A class/object is a test class when annotated `RunWith`/`ExtendWith`/
`TestInstance`, when it directly declares an annotated test function, or when it
extends a Kotest spec (`StringSpec`, `FunSpec`, `DescribeSpec`, `BehaviorSpec`,
`ShouldSpec`, `WordSpec`, `FreeSpec`, `FeatureSpec`, `ExpectSpec`,
`AnnotationSpec`). Adjacent `/** */` KDoc is included.

### Python (best effort)

- `class_definition` whose superclass's last dotted component ends in `TestCase`
  (`unittest.TestCase`, `IsolatedAsyncioTestCase`, Django `TestCase`/
  `TransactionTestCase`/`SimpleTestCase`, DRF `APITestCase`).
- Only when the module imports `pytest`: module-level `test_*` functions (sync or
  async), `Test*` classes, and definitions decorated with `pytest.fixture` or
  `pytest.mark.*`. Without the import a `def test_connection()` is treated as
  production API.
- `decorated_definition` is the region, so decorators hide with the definition.
- Not detected: doctests, `if __name__ == "__main__"` runners, nose/ward styles,
  dynamically generated tests.

### TypeScript, TSX, JavaScript

- Program-level `expression_statement` whose call's callee root is `describe`,
  `it`, `test`, `suite`, `context`, `xit`, `xdescribe`, `fit`, `fdescribe`,
  `beforeEach`, `afterEach`, `beforeAll`, `afterAll`, or `Deno.test`, including
  member chains (`.only`, `.skip`, `.each(...)(...)`, `.concurrent`), with at
  least one function argument (arrow/function expression) in the outermost call.
- The root identifier must be unbound in the file or imported from a test module
  (`vitest`, `bun:test`, `@jest/globals`, `node:test`, `mocha`,
  `@playwright/test`, `jest`, `uvu`, `ava`). A local declaration or an import
  from anywhere else (`import { test } from "./regex"`) makes it production.
- `if (import.meta.vitest) { … }` in-source tests only without an alternative.
  An else/else-if keeps the entire statement visible, conservatively preserving
  production; test calls nested inside it are not separately hidden.
- Not detected: tests inside function bodies, custom wrappers, Cypress/Jasmine
  globals beyond the names above.

### Region normalization

Expanded to whole lines when only whitespace precedes the start and follows the
end on their lines (the trailing newline stays, so production resumes on its own
line). Nested regions collapse to the outermost. Consecutive regions separated
only by whitespace merge (e.g. tkos `app.rs` 35–43). A region never consumes a
following item's doc comment or production code.

## Presentation (projection, not mutation)

Source bytes, TextKit storage, Tree-sitter input and SCIP input are unchanged.

- **When applied:** Hide Tests is on, the document is not itself a test document
  (path classifier or `#![cfg(test)]`), and syntax for exactly this path/content
  is present. A test document opened explicitly (⌘K, search, navigation) is shown
  in full with a quiet “Test file” footer note; hiding its contents would leave
  nothing to read.
- **Shape:** each region keeps its first line (e.g. `#[cfg(test)]`, `@Test fun …`)
  as a dimmed header; the rest is hidden through the existing fold machinery
  (null glyphs, zero-advance control characters). Hidden test ranges and fold
  ranges are unioned into one sorted disjoint set. The header is dimmed with the
  existing draw-time receded alpha, merged with Critical Lens' receded ranges.
- **Affordance:** the gutter shows the fold disclosure ▶ and the existing 9-pt
  hidden-line capsule on the header row (taking precedence over a fold marker on
  that row); its tooltip/accessibility says “Test code — N lines hidden”. A quiet
  inline label after the header text reads “Test code · N lines hidden”; when
  revealed it reads “Hide test code”. Either control toggles that one region.
  Line numbers stay canonical: the gutter shows 803 then 834.
- **Reveal state** is `AppModel.revealedTestRegions` (region start bytes) for the
  loaded document. It resets when another document loads (including identical
  bytes at another path, Before/After switches), on repository open/reload, and
  whenever Hide Tests is turned on.
- **Navigation:** any explicit navigation (definition, references, outline,
  breadcrumbs, search result, Go to Line, history) whose target is inside a hidden
  region reveals that region first; when syntax arrives after the jump, the
  pending target is revealed at that time. A plain file open at its default top
  does not reveal. Back/Forward use the exact recorded locations. Folds
  containing the target are removed as before.
- **Outline:** declarations inside hidden regions are omitted; they reappear when
  their region is revealed or the option is off. Breadcrumbs and Context use the
  full syntax.
- **Copy/find:** like folds, copy of a range spanning a hidden region yields the
  exact source bytes, and the find bar searches the full text. Keyboard movement
  behaves as across a collapsed fold.

## Synchronization and identity

- `fileTree`/`visibleFileCount` are recomputed on repository publish (including PR
  snapshots and reload) and on option changes; the file-query list too.
- The viewer applies a `TestCodePresentation` only when its path and
  `SourceContentIdentity` match the buffer in TextKit, like `SourceProjection`.
- Syntax for a stale path/generation is already discarded by `AppModel`.

## Tests

`TestRegionDetectorTests` (language positives/negatives, cfg logic, boundary,
Unicode/CRLF), `SourceFilterTests` (path classifiers, artifacts, pruning,
independence, order), `TestCodePresentationTests` (header/hidden ranges, merge
with folds, TextKit null glyphs and gutter line numbers, reveal on navigation,
Back, toggling, stale identity), and an opt-in real tkos probe
(`RADIOLOGY_REAL_TEST_FILTER_PROBE=1`).

## Outcome (2026-10-04, Opus 5.5)

- Gates: `make check`; `make test` **210 tests / 43 suites** (the three
  `TestFilterRealDataProbe` tests skip unless opted in); `make build`
  (swiftbuild); `codesign --verify --deep --strict`; `env -i
  --verify-resources` from `/tmp` (8 grammars). Signed binary **2026-10-04
  23:16:01 CDT**.
- Opt-in real tkos probe (`RADIOLOGY_REAL_TEST_FILTER_PROBE=1 swift test
  --filter TestFilterRealDataProbe`), read-only, passed:
  - `modules/agent/ffi/src/app.rs`: 35–43, 803–833, 3424–4709. Line 834
    `create_durable_agent` and line 44 production are outside.
  - `engine/rust/src/snapshot_policy.rs`: 16–108, with `configure` (line 9)
    visible.
  - `fonts/src/test/kotlin/inc/tk/os/fonts/FontFilesTest.kt` 9–87,
    `scripts/test_pr_local.py` 22–179 and `scripts/home-design-inspect.test.ts`
    22–58 cover Sol's anchors (12/27/43, 22/70, 22/31). Production
    counterparts `FontFiles.kt`, `pr-local.py` and `home-design-inspect.ts`
    have none. All three anchor files are whole test files by path, so the
    reader shows them in full (“Test file”) and the Files tree hides them.
  - Files: Hide Tests 4,842 / 6,846; Source Files Only 5,198; both 3,256.
  - Whole-repository sweep of non-test paths (63 s, no failures): Rust
    183/289 files contain test code (229 regions); Python 6/173; TypeScript
    1/947; Kotlin 0/1,490; JavaScript 0/151; TSX 0/207. Every non-Rust hit was
    inspected and is a true positive: in-script `unittest.TestCase` classes and
    `scripts/bun-test-preload.ts`'s `beforeEach`.
- Preview without the UI: `defaults write com.muchanem.marin-viewer hideTests -bool YES`
  (and `sourceFilesOnly`) before launch; the toggles reflect it.
- Not verified: live UI (toggle look, label legibility in light/dark,
  click targets, pointer cursor, narrow sidebar, VoiceOver reading). Owned by
  GPT Sol in [source-filters-ui-review.md](source-filters-ui-review.md).

## GPT Sol acceptance repairs (2026-10-04)

Current gates: 213 tests/43 suites, check/build/strict codesign/env-i resources,
signed 23:23:22 CDT. pytest function names require test_ exactly. Vitest if/else
remains visible. Label hit IDs refresh independently of geometry, and label
visibility checks the actual header glyph (null/not-shown headers cannot paint
or hit on a folded ancestor). Model and AppKit regressions pass; two targeted
real-tkos probes rerun, full sweep remains Opus's recorded earlier evidence.
Native attachment selected the older shared reader twice and stopped without
actions/screenshots. See source-filters-ui-review.md; no live acceptance claim.

## PR Changes scope superseded — 2026-10-05

Both options now apply to Changes as well as Files using shared includes policy.
Canonical PR changes/diffs/indexing/navigation/search remain complete. Deleted
uses Before; rename/copy includes if either available path passes BOTH active
options. Visible counts/text-file totals and distinct filtered-empty/reset keep
scope honest; selection sync never navigates the excluded current reader.
Gates 216/44, signed 19:00:13 PDT, check/build/strict signing/resources/diff check.
No live check; see source-filters-ui-review.md. Historical Changes-unfiltered
statements are superseded by this user request.
