# Kotlin semantic indexing

Implemented 2026-10-07 after PR #758's After `Contacts` Kotlin source showed
"File not indexed", no under-caret semantic target, and unavailable references.
The previous implementation had Kotlin Tree-sitter structure but no JVM SCIP
adapter. The user explicitly selected **Add Kotlin semantic support**.

## Requirements

- Use actual compiler-resolved Kotlin identities for definitions/references;
  never promote spelling matches to semantic navigation.
- Index exact PR After bytes and keep Before syntax-only.
- Support the tkos Android Gradle build, including built-in Kotlin in AGP 9,
  as well as ordinary JVM Gradle projects where feasible.
- Keep the attached checkout read-only. Build/indexing intermediates belong
  in an isolated app-owned workspace. Preserve real manifests, dependencies,
  source layout, compiler versions, and package identity.
- Integrate with existing tool provisioning, per-strategy diagnostics,
  cancellation, exact-content provenance, document mapping, Context, and Back.
- Validate a real compiler-produced index, then PR caret/reference/definition
  navigation with exact departure history and revision isolation.

## Tooling choice

Upstream [scip-java](https://github.com/scip-code/scip-java) now includes the
Kotlin compiler plugin. Latest published CLI inspected: v0.13.1 (2026-07-02).
Its [automatic-indexing documentation](https://github.com/scip-code/scip-java/blob/main/docs/getting-started.md)
does not support Android. Inspection of its current Gradle plugin confirms
it only attaches to legacy Kotlin/JVM or multiplatform plugins, and assumes
the old `getKotlinOptions` API. This does not justify treating a generic
`scip-java index` adapter as a fix for tkos.

tkos currently uses AGP 9.4.1, Kotlin 2.4.20, Gradle 9.7.1, and Android
modules with built-in Kotlin. The new attachment and pinned compiler plugin
were validated against that build. No project reconfiguration or synthetic
source-only manifests were used. Research/builds took place under /tmp and
Application Support, outside the attached checkout.

## Implementation and invariants

- `ScipKotlinIndexer` detects actual Gradle roots with `.kt`/`.java`; one
  strategy covers subprojects. Source folders and Gradle scripts alone do
  not fabricate a project. The strategy id is `scip-kotlin`.
- Managed tool version `0.13.1-radiology-9f288dd339c7` pins upstream source
  commit `9f288dd339c7e9fc257a7b21714d9a402fd4d837`, with Kotlin2.4.20
  compatibility. Do not substitute the published v0.13.1 Kotlin2.2 plugin
  without compatibility proof. The installed tool was version-verified here.
- `IndexingScripts/install-kotlin-indexer.sh` builds the CLI/plugins under
  `~/Library/Application Support/Radiology/tools/kotlin-scip/`, with JDK17+.
  Gradle9.7.1 is reused from a wrapper cache or downloaded with its official
  SHA256 check. Existing ToolProvisioner/version checks/Install UI are used.
- `IndexingWorkspace` copies actual inputs, preserving layout/bytes/modes.
  The new adapter opts into `requiresIsolatedWorkspace`; existing adapters
  keep their defaults. Snapshot/working-tree blob ids verify copied inputs;
  a post-build hash check rejects builds that rewrite tracked source/manifests.
  Traversal is rejected, internal file/directory links are rebased into the
  copy and verified by link text, external source/build
  links rejected. External Markdown instruction links keep their Git link bytes.
- `kotlin-index.gradle` uses current `compilerOptions`, including AGP9 built-in
  Kotlin. Aggregate tasks register early, but compile-task discovery waits for
  `projectsEvaluated`: Android variant tasks do not exist during ordinary
  `afterEvaluate`. JVM main/test and Android debug/unit-test Kotlin/java compile
  tasks are included; tests are compiled rather than executed.
- `kotlin-index.sh` starts with empty shards and runs real Gradle with no
  configuration/build cache, no persistent daemon, and in-process Kotlin.
  Independent successful compiler output survives failures via aggregation;
  a failure marker yields `partialBuild` on generation and cache/reuse.
  Empty usable output fails. Existing process-group cancellation is retained.
  The build uses actual dependencies and declared project build steps, which
  may execute during compilation. No manifests, dependencies, or sources are
  rewritten to make a missing project compile.
- Generation/cache/reuse filter compiler documents to actual source inventory.
  Generated files present only in the disposable copy are never navigable
  definitions in the pinned reader. Counts describe accepted documents.
- The Kotlin plugin uses UTF-16 columns in UTF-8 source and can omit document
  position encoding. `SemanticIndex.Input.defaultEncoding` now carries the
  adapter's contract on all three index-loading paths. Explicit document
  encoding wins. This fixes tokens after accented text/emoji.
- Context/caret, references, Return/definition, symbol search and exact Back
  use real compiler identities. PR destinations force After; Before never
  receives the After occurrence map. No spelling-based navigation is added.
- The existing diagnostics row adds an explanation for Partial build coverage.
  It uses SF Pro semantic callout (`Theme.Fonts.meta`), regular weight,
  secondary color and native wrapping/leading; no new type scale or source
  styling. Applied swiftui-pro before/after, macos-design, typography-designer.

## Measured evidence

Exact PR758 head: `5d2ffdd2976c62a220118e30780edfe8fb6f2120`. The real build ran
under `/private/tmp/radiology-kotlin-pr758`, copied from the app-owned pinned
head tree, rather than the attached checkout.

- Contacts plus dependencies/unit tests: successful compilation, 112 compiler
  documents. The screenshot's `addSecrecyTag` on line141 resolves to
  `core/src/main/kotlin/inc/tk/os/module/SecrecyCtx.kt:18`.
- Broader build: 1,276 Gradle tasks, 2m03s, 2,379 compiler documents.
  `installRustAndroidTarget` and `installUniffiBindgen` failed in the manual
  shell environment; coverage is honestly Partial. No complete-build claim.
- `KotlinRealDataProbe` maps 1,355 Contacts occurrences from that broader
  index, resolves the same definition, and loads **18 references in 4 files**,
  with zero unreadable reference files and zero unmapped references.
  One generated companion constructor has an invalid oversized upstream range;
  it stays unmapped. The probe allows only generated-constructor omissions,
  never unmapped ordinary call tokens.
- All **10,394 copied tracked inputs** are byte-identical after compilation.
  The attached tkos Git status is unchanged between checks.
- A **4,119-byte real compiler fixture**, with source/provenance in
  `Tests/.../Fixtures/scip-kotlin`, tests overloads, an unrelated same-spelled
  function and UTF-16 columns after café/emoji.
- Temporary Git PR integration tests prove native NSTextView selection
  notifications update Context on a changed Kotlin call line without navigation;
  Find References, definition/reference commits, After routing despite Before
  preferences, passive-scroll departure, exact Back, Before clearing, After
  remapping, and metadata-only refresh pass.
- Cache/reuse tests preserve UTF-16, Partial status and the source inventory
  boundary. Isolation tests cover bytes/modes, links, stale input rejection,
  traversal, original checkout immutability and build-rewritten input rejection.

Final gates: **241 tests / 50 suites**, make check/build, strict deep codesign,
empty-environment packaged resources (eight grammars/three scripts), and diff
checks pass. Signed **2026-10-07 18:36:00 PDT**. An initial full-suite run during
Gradle compilation hit an existing 5-second subprocess deadline at 5.62s; idle
full-suite runs passed without changing that test.

Logs: `/tmp/radiology-kotlin-pr758-compile.log`,
`/tmp/radiology-kotlin-pr758-full.log`, `/tmp/radiology-kotlin-full-real-probe.log`,
`/tmp/radiology-kotlin-install.log`, `/tmp/radiology-kotlin-all-tests.log`,
`/tmp/radiology-kotlin-build.log`. Raw output:
`/tmp/radiology-pr758-full-kotlin.scip` (broader) and
`/tmp/radiology-pr758-kotlin.scip` (targeted). Raw artifacts include generated
documents; production publication enforces the source inventory boundary.

## UI and compatibility boundary

No physical UI launch, pointer reference commit, or screenshot recheck occurred;
the user's reader was left running. Relaunch the signed app to use the new
registry; Kotlin indexing then runs automatically for the active source root.
The compiler tool is already installed on this machine.

Manual acceptance: PR758 After, ContactsModule.kt line141, move/select inside
`addSecrecyTag`; verify Definition and Find References, commit a row and Cmd-[
to the exact departure caret. Repeat after scrolling and across Before/After.
Partial status should explain failed modules while covered Kotlin stays usable.
The preceding inspector-recovery manual checks remain open.

Validated compatibility is Kotlin2.4.20/AGP9.4.1/Gradle9.7.1/JDK17. Other compiler
versions may need a matching plugin. Kotlin scripts/non-JVM multiplatform
targets remain unclaimed. Independent nested Gradle builds not included by a
detected ancestor can remain uncovered and appear in its missing-file list.

## 2026-10-08 production preparation repair

The user's real app failed before invoking Gradle: harness-development is a
tracked directory symlink. Materializing it and hashing it as a file was wrong.
The earlier manual Python copy skipped directory links, so its compiler success
did not cover this production path.

`IndexingWorkspace` now recognizes link kinds without following them first,
rebases internal file/directory/dangling links to copied targets, and hashes/
verifies their link text plus input kind. Original link bytes still validate
snapshot blob ids. Links cannot keep pointing into the original checkout.
It resolves a link's literal destination rather than asking Foundation to
resolve the source link: a dangling AGENTS.md pointed at
/Users/kurt/code/tkos-workflow/AGENTS.md and otherwise appeared internal when
resolution failed. External Markdown links keep their Git bytes as a file;
external build/source links remain rejected. Copied file kinds are checked
before post-build reads; link redirection is rejected.

Compiler inputs now include every path in the snapshot blob inventory, not
only `RepositorySnapshot.files` (which deliberately excludes vendor/build).
Git working trees list complete tracked/nonignored inputs for fingerprints,
digests and copying. Gradle's actual vendored dependencies therefore survive
browser filtering and their changes invalidate caches. Reader-index publication
still excludes documents outside the source inventory.

Tests reproduce the exact .agents/.claude directory alias plus absolute links,
dangling Markdown/internal links, input tampering and a tracked excluded
dependency. The new opt-in `actualPR758IndexesThroughTheApplicationService`
probe uses the real repository listing, workspace factory, installed adapter,
build, verification and publication. Flag:
`RADIOLOGY_REAL_KOTLIN_SERVICE_PROBE=1 swift test --filter actualPR758IndexesThroughTheApplicationService`.
Its cache is temporary; it reads the existing pinned head tree and never builds
in the attached checkout. It passed in **178.684s**, publishing **2,088 actual
source documents** with generated/partialBuild status, cache metadata verified,
and workspace removed after publication. The real token/definition and **18
references in 4 files** resolve against the pinned reader tree after cleanup,
with no unreadable/unmapped references. This supersedes the earlier manual copy
as evidence for the complete production path. The attached checkout's Git status
remains unchanged.

The working-tree service regression also proves a tracked vendor dependency is
copied despite browser exclusion and that changing only its bytes invalidates
the cached index. Focused 6 tests and full **244 tests / 50 suites** pass, plus
check/build/strict deep signing/empty-environment packaged resources/diff check.
Signed **2026-10-08 01:10:35 CDT**. Logs: /tmp/radiology-kotlin-service-probe.log,
/tmp/radiology-kotlin-directory-tests.log, /tmp/radiology-kotlin-link-tests.log,
/tmp/radiology-kotlin-link-build.log. Physical app interaction remains unverified;
relaunch the rebuilt app and reopen PR758 for automatic Kotlin retry. Partial
coverage remains truthful for uncovered sources/variants.
