# Radiology

Radiology is a native, read-only macOS code browser for understanding unfamiliar repositories. It combines Git-aware file discovery, a TextKit source reader, ripgrep search, Tree-sitter structure, and optional SCIP semantic navigation. It is intentionally not an editor and does not run language servers.

## Requirements and quick start

- macOS 14 or newer
- Swift 6.2 or newer (Xcode or a standalone Swift toolchain)
- `ripgrep` (`rg`) for repository-wide text search; browsing and reading work without it
- language-specific SCIP indexers only when semantic navigation is wanted (see below)

```sh
make run       # debug build, assemble/sign build/Marin Viewer.app, then open it
make build     # debug build and assemble/sign build/Marin Viewer.app
make check     # compile with SwiftPM; no app bundle or signing
make test      # run the Swift Testing suite
make release   # release build into build/Marin Viewer.app
make help      # all build/install/distribution targets
```

The active project is this root Swift package, tracked at [tqbf/radiology](https://github.com/tqbf/radiology). An inherited local `repo/` starter copy is ignored by Git and must not be edited. Release targets require the matching Git tag and any configured signing/notarization credentials described in [the build guide](plans/build-system.md).

## Open and navigate

Open a folder from the toolbar’s **repository dropdown > Open Repository…**, **File > Open Repository…**, a recent-folder entry, Finder drag and drop, or the development launch arguments below. The toolbar groups navigation/repository, labeled PR context, and viewing tools. Its search menu contains Go to File, Go to Symbol, and Search Repository; Source Files Only and Hide Tests live in the View menu. The source-mode dropdown shows Normal initially; Before/After sits beside it during review. Repository discovery uses `git ls-files` when possible and otherwise walks the folder while excluding common generated/vendor directories.

The primary workflows are:

- Browse or filter the repository tree, or use fuzzy **Go to File**. Queries are ordered subsequences: for example, `engrs` can match `engine-foo.rs`.
- Read syntax-highlighted source with original line numbers, outline, breadcrumbs, default-collapsed function bodies, and exact Back/Forward history.
- Search the current file with the native Find panel or the repository with ripgrep literal/regex, case, and glob controls.
- With a SCIP index, Command-hover a resolvable occurrence, Command-click or invoke Go to Definition, inspect references, and search repository symbols.
- Single-click a symbol to highlight its current-file occurrences. Double-click locks an occurrence group; several teal/amber/violet/rose groups may coexist, and double-clicking any member unlocks only that group. When SCIP omits cfg-inactive code, a Tree-sitter fallback highlights exact same-spelled identifiers inside the innermost function only; it is never used to guess definitions or references.
- Review a GitHub pull request of the attached repository: pick one of the last 25 from the toolbar's **Pull Request** menu or press ⌘P and type a number. See [Pull request review](#pull-request-review).

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘O | Open repository/folder |
| ⌘K | Go to file (fuzzy) |
| ⌘P | Open pull request by number |
| ⌘T | Go to semantic symbol |
| ⌘L | Go to line |
| ⌘[ / ⌘] | Back / Forward |
| ⌘F, ⌘G, ⇧⌘G | Find in file / next / previous |
| ⇧⌘F | Search repository |
| ⌃⌘J | Go to definition at caret |
| Arrow keys (in source) | Move a thin, steady caret (shown only in the focused reader with nothing selected) and update the Context inspector, without navigating |
| x (in source) | Expand/collapse the innermost function at the caret; no action outside a foldable function |
| Return / Enter (in source) | Go to the definition of the symbol at the caret or the selected word. ⌘[ returns to the exact caret |
| ⌃⌘R | Find references at caret (pins them in the Context inspector) |
| ⌃⌘I | Reindex repository |
| ⌥⌘I | Show / hide the Context inspector (also in the View menu) |
| ⌘R | Refresh active PR from GitHub; outside PR, reload repository |
| ⌥⌘0 | Fold to Definitions |
| ⇧⌘0 | Collapse Functions |
| ⌃⌘T | Hide Tests (View menu toggle) |
| ⌃⌘O | Source Files Only (View menu toggle) |
| ⌘+ / ⌘− | Increase / decrease source text size |
| ⌘D | Add/remove bookmark at the source caret |
| ⌘0…⌘9 | Open the first ten bookmarks, in their current order |
| ⇧⌘P | Import a code path from pasted text or a text file |
| ⌃⌘P | Show Code Paths in the left sidebar |
| ⌥⌘1 / ⌥⌘2 | Source mode: Normal / Critical Lens (toolbar dropdown) |
| ⌥⌘B | Toggle Before/After for the open file of a pull request |
| ⌥⌘↓ / ⌥⌘↑ | Next / previous changed block in the current file/revision (skip current block; no wrap) |

The complete [keyboard reference](Sources/Radiology/Help/KeyboardShortcuts.md) is also available in **Help > Keyboard Shortcuts…** (⌘/). It includes all menu shortcuts, reader keys, focus-specific sidebar controls, sheets, and native macOS bindings.

The source breadcrumb keeps nearby directories and enclosing declarations visible
as space allows, shortening distant path entries first. File/final declaration
get priority at tight widths; **…** shows the full path and all declaration jumps.
Changed-block and collapse controls stay on the right; Before/After is beside the source-mode dropdown in the main toolbar.

The right-hand **Context** inspector follows the caret and is concise by default: one line per item. Use its **Panes** menu or **View > Context Panes** to enable or disable References, Definition / Outline, Implementations and Bookmarks. Choices persist across relaunches; **Show All Panes** restores them, including when every pane is disabled. Implementations remains contextual; disabling it reveals Definition / Outline when enabled. Remaining panes share the available height. Dragging the outer divider far enough to the right collapses the whole inspector. Restore it with **View > Show Context Inspector**, **⌥⌘I**, or the toolbar's **Show Context Inspector** button (`sidebar.right`). Enabling a pane from View also reopens the inspector. These controls work without an open source file.
- **Symbol and References:** a prominent enclosing-declaration name with kind/file:line, followed by compact references. ↑/↓ selects a reference. → (or its triangle) shows source context and the containing function's caller tree. Each caller is a clickable pill with a stable color from its method name and file. Pills open their call sites; recursive branches stop before repeating a function, and unknown boundaries are marked. Large trees offer **Trace more callers**. Return or double-click opens the reference, and ⌘[ returns to the exact caret.
- **Definition:** sits below References, with location/Here; a matching symbol name is omitted, while a different caret target remains named. Its triangle reveals signature, docs, and a source preview. Go there with the link, Tab then Return, ⌃⌘J, ⌘-click, or Return in source. Whitespace/keywords show the outline. Moving the caret never moves source. ⌃⌘R pins references until **Follow Caret**.
- **Trait Implementations:** a dense flat list of explicit indexed impls while reading a trait, its members, its name in a reference, or its impl blocks. Click a type row to open the impl; ⌘[ returns to the exact caret. ↑/↓ selects and Return opens. Compact file:line metadata shares each row; help retains full paths/signatures, and negative impls are marked. Results are precomputed/cached; a coverage icon explains gaps. Macro-generated and inactive impls may be absent.
- **Bookmarks:** a third pane saves locations separately for the attached repository's checkout and each PR. ⌘D or the bookmark button toggles the caret location. The first ten rows use ⌘0…⌘9; drag to reorder, or use Move Up/Down/Move to Shortcut in the context menu. Click any row to open it, preserving its Before/After revision; ⌘[ returns to the exact departure caret. Order persists across relaunch.

**Code Paths** lives in the left sidebar alongside Files, Changes (during PR review), and Search. It holds agent-generated traces such as an OS boot sequence. Choose **Repository > Import Code Path…** (⇧⌘P), paste a blob or choose a UTF-8 text file, and import. The first line is a title; each later line is `file:function:description`, with repository-relative paths and actual declaration names. Functions are resolved in the current source, so inserting lines above them does not break the trace. Qualify ambiguous methods (e.g. `Kernel.boot`), or use an exact declaration header to distinguish overloads. Escape colons in function names as `\:` (e.g. `Kernel\:\:boot`); descriptions can contain colons. Multiple traces persist per attached repository, shared with its PRs. Select a trace, then click a step or press Return to jump; ⌘[ returns to the departure caret. PR steps open After. Import selects Code Paths and reveals the left sidebar. **View > Show Code Paths** (⌃⌘P) does the same without importing. Bookmarks remains independently controlled in the right inspector. Its actions menu also copies or deletes a trace. Conditional source alternatives open the first definition and offer a menu for the others. [Reusable generator skill prompt](plans/code-path-generator-prompt.md).

Drag the horizontal dividers to resize References, Definition/Outline/Implementations and Bookmarks;
each pane scrolls independently. Smaller
headings and primary monospace snippets distinguish labels from code; faint
blue/teal/purple/neutral backgrounds mark sections in light and dark appearances.

The sidebar uses **Changes / Files / Code Paths / Search** tabs (Changes during PR review). Full titles give way to labeled SF Symbols when the sidebar is narrow; arrow keys and accessibility labels work in either layout. Changed-file rows keep two lines: a primary filename and quieter path, with right-aligned tabular counts. **M** means modified; circled plus means added. The selected row has a subtle accent marker. Footer counts name active filters, for example **18 of 30 files · Source only · Tests hidden**. The PR head is available in the Git icon’s tooltip.

Files follows source navigation: parent folders expand, the current file is
highlighted and scrolled toward the center, including when returning from Search
or following bookmarks. The current file stays visible through filters; Before-only
PR files carry a Before label. Filter settings and the exact source caret remain.

### Critical Lens

**Critical** (source-mode dropdown in the toolbar, or ⌥⌘2) focuses on call names. Most source recedes: keywords, punctuation, strings/numbers/constants, types, locals/receivers/fields, comments and declarations. Only actual parsed call-name tokens can remain prominent. Repository, system/FFI and user-critical calls stand out; proven ordinary runtime calls stay dim. Unknown/unresolved syntactic calls remain visible without inventing an indexed identity or call edge. A critical mark on non-call text does not promote it. This is drawing only: text, layout, coordinates, copy, selection, pins, folds and history stay unchanged. Call syntax is required, but a semantic index is optional for rendering; without one all named calls are unknown. ⌥⌘1 restores full Normal syntax contrast.

The Context sidebar is the same in Normal and Critical: concise declaration/references above and Definition/outline below, with the existing disclosures and navigation. It has no lens summaries, frontiers or density counts. Resting the pointer on an indexed callable in Critical mode opens a compact frontier popover; move into it and click the symbol name or any whole navigable row (not just the trailing location), and ⌘[ returns to the caret. External/missing definitions are unavailable rather than guessed. Collapsed source functions retain reachable-critical gutter counts (`3`, `3+` for a lower bound, `–` for no body). Edges come only from parsed call sites resolved to indexed symbols; closures, macros, unresolved dependencies and unknown callees keep coverage honest.

Right-click a symbol for **Mark “name”** and **Mark Package “pkg”** submenus (Critical, Non-Critical, Built-In). A symbol mark beats a package mark, and both beat the built-in policy. Marks persist per repository at `~/Library/Application Support/Radiology/overrides/<repository-id>.json`; locals cannot be marked because their index numbers change on reindexing. Only the rust-analyzer scheme has built-in profiles; other indexers classify repository symbols only.

The outline starts with all file functions/methods, including nested ones, largest to smallest with a quiet line count; other declarations follow in a native hierarchy. This ordering is identical in Normal/Critical. Outline Up/Down previews a declaration and Return commits it to navigation history. Clicking an outline item commits immediately and unfolds any ancestors that hide the destination. The source gutter is 72 points wide and shows every fifth canonical line number plus the actual caret line. Numbers remain small UI metadata when source text is enlarged. Fold disclosure targets occupy a 20-point lane; collapsed functions retain a size meter and count badges when space permits, with exact counts in tooltips/accessibility.

### Source filters: Hide Tests and Source Files Only

Two independent toggles sit beside the **Filter files** field in the Files sidebar and in the View menu. Both persist app-wide and are off by default.

- **Source Files Only** (⌃⌘O) narrows the Files tree to code and headers (Swift, Rust, Go, Python, JS/TS, Kotlin, Java, C/C++/Objective-C and many more). It hides documentation, data, manifests and configs (`Cargo.toml`, `package.json`, `Package.swift`, `*.config.ts`), build outputs and dependency trees (`target/`, `build/`, `dist/`, `out/`, `node_modules/`, `vendor/`, `.venv/`, hidden directories), and generated files (`*.min.js`, `*.pb.go`, `*_pb2.py`, `*.generated.*`). A `.rs` file under `target/` is not source.
- **Hide Tests** (⌃⌘T) removes recognized test files and directories from the Files tree. It also hides test code inside ordinary source. Each hidden region keeps its first line (for example `#[cfg(test)]`) as a dimmed header with a quiet “Test code · N lines hidden” label. The gutter shows a disclosure and a hidden-line count; line numbers remain canonical with sparse fifth-line/caret labeling. Click the label or the disclosure to show the region; “Hide test code” hides it again. Detection reads parsed syntax:
  - **Rust:** `#[cfg(...)]` items that no non-test build compiles, including inside `impl` blocks. `cfg(any(test, feature = "x"))` stays visible.
  - **Rust:** `#[test]`, `#[tokio::test]`, `#[rstest]`, `#[test_case]`, and modules or files with `#![cfg(test)]`.
  - **Kotlin:** JUnit/kotlin.test annotations, test classes, and Kotest specs.
  - **TypeScript, TSX, JavaScript:** top-level `describe`/`it`/`test` calls unless the file binds those names itself (`Deno.test` included), and Vitest `if (import.meta.vitest)` blocks.
  - **Python (best effort):** `TestCase` subclasses, plus pytest functions, classes and fixtures in modules that import pytest.
- Explicit navigation into hidden test code reveals that region first. This covers definitions, references, outline, search, Go to Line and Back/Forward; ⌘[ still returns to the exact departure. Hidden declarations leave the outline until revealed. A test file you open directly is shown in full; its footer reads **Test file**.
- Hiding is presentation only. Source bytes, copy, find, Tree-sitter and SCIP input are unchanged, and manual folds survive toggling.
- Files and PR Changes use both filters; Changes keeps a rename if either available path passes. Its counts/totals describe visible rows, and Show All Files resets a filtered-empty list. ⌘K, repository search, Go to Symbol and indexing always cover every file. The open file stays open when filtered out; the sidebar footer then says so. **Show All Files** turns both options off when nothing matches.

See [plans/source-filters.md](plans/source-filters.md) for the exact rules and limits.

### Pull request review

Radiology remembers the last repository and successfully opened PR and reopens
them on relaunch, fetching current PR metadata. **Exit PR** remembers local
checkout instead. Explicit launch arguments take precedence. A failed restore
keeps the saved PR available for retry; source selection and caret positions are
session-local. See [session restoration](plans/session-restoration.md).

The toolbar's **Pull Request** menu (next to Back/Forward) lists the last 25 pull requests of the attached repository, open, merged, or closed, as `gh` reports them; **Open Pull Request…** (⌘P) takes any number. Opening one shows the **Changes** sidebar tab: filtered changed files with visible-of-total counts, status, `+n −m` counts, and old → new paths for renames. Files containing changes carry a small accent dot in the file tree and in the outline's callable rows; added lines carry a green gutter bar and a faint green wash, removed lines (in Before) the same in red. Small up/down buttons at the right of the breadcrumb row and ⌥⌘↓/⌥⌘↑ jump between changed blocks. From inside a block they skip it; from a gap they choose the nearest block in that direction. Ends disable without wrapping; ⌘[ restores the exact departure caret. The selector visibly names the PR (`#758`); its full title stays in Changes and the PR menu/help. **Exit PR** is the first action in that dropdown while active/loading and returns to the attached local checkout (or cancels a pending review), without switching branches. **Local Checkout** is the selected menu row outside a review.

PR files initially open functions/blocks containing changes, including nested ancestors and signature/annotation-only edits, once syntax and exact-revision hunks are available. Unchanged functions keep normal default folding. Manual fold choices win, including while changes load; Hide Tests stays in force. This is one-time default presentation, not navigation.

The compact **Refresh PR** icon beside the selector (also in the Pull Request menu, ⌘R) fetches the latest head and merge base without leaving review. **Refresh List** only updates the menu list. The current reader stays usable during fetch; failures leave it intact and Try Again retries refresh. If head/base are unchanged, only metadata updates. Otherwise the latest caret/viewport are retained by exact bytes or Git line mapping, and SHA-obsolete history is cleared. Renames follow Git metadata; unavailable revisions or missing files show a quiet notice. Only exact-byte current-file pins survive a snapshot change. No Git branch changes or automatic polling.

Every changed file has a **Before | After** control beside the source-mode dropdown in the top toolbar. **After** is the pull request's pinned head commit; **Before** is the merge base GitHub's own diff uses, never the reader's checkout or the moving base branch. Switching keeps the caret on the corresponding line and records history, so ⌘[ returns to the exact spot in the other revision. Added files have no Before, deleted files no After, unchanged files are identical in both, and binary files are listed but not shown as text.

Semantic navigation, references, previews, and Critical Lens edges in a review come from an index of the **After** snapshot. The **Before** revision is deliberately not indexed: its footer reads **Not Indexed (Before)**, structure browsing still works, and no index is ever mapped onto Before bytes. The After index reuses a project only when the entire repository byte context matches an existing index (git blob IDs, metadata format 3, versioned digest); sibling dependency inputs are not yet modeled, so any repository byte change conservatively invalidates reuse. The rest is regenerated whole. A run/cache that mixes reused and regenerated projects or different reuse origins stays **Partial**, including after reload, because references from a reused project into a regenerated one may be outdated. Indexes generated before this format carry no byte provenance and are never reused for a review; one Reindex of the checkout records it.

Requirements: `git`, the GitHub CLI `gh` logged in (`gh auth login`), and an `origin` remote on GitHub. Radiology fetches commits by SHA into its own bare repository under the cache (reading the attached repository's objects, never writing them), checks the head out into its own worktree, and keeps the three most recently used worktrees. Nothing is written to GitHub and nothing is changed in the attached folder.

## Syntax languages

Tree-sitter highlighting, declarations/scopes, outline, breadcrumbs, and folding are bundled for:

| Language | Extensions |
| --- | --- |
| Swift | `.swift` |
| Rust | `.rs` |
| Go | `.go` |
| Python | `.py`, `.pyi` |
| JavaScript / JSX | `.js`, `.jsx`, `.mjs`, `.cjs` |
| TypeScript | `.ts`, `.mts`, `.cts` |
| TSX | `.tsx` |
| Kotlin | `.kt`, `.kts` |
| C | `.c` |
| C++ | `.C`, `.cc`, `.cpp`, `.cxx`, `.c++`, `.h`, `.hh`, `.hpp`, `.hxx`, `.h++`, `.ipp`, `.inl`, `.tpp`, `.tcc` |

These are ten grammar registrations backed by 47 Radiology query resources. Ambiguous `.h` headers use the C++ grammar, which also handles common C declarations. Unsupported extensions remain readable as plain UTF-8 text. Files over 16 MiB are rejected. Source locations are canonical UTF-8 byte offsets; conversion to UTF-16 happens only at TextKit and semantic-index boundaries.

## Semantic indexing

The Semantic Index popover includes a **Personality** menu, remembered per
repository. **Default** detects projects normally. **seL4** generates real
headers and indexes a TOML-defined configuration matrix as separate compiler
runs, retaining conditional definitions in a union on every Reindex. **Show
Settings File** reveals the editable TOML under
`~/Library/Application Support/Radiology/IndexingPersonalities/`. Settings
changes take effect on Reindex; each personality has its own cache. See
[indexing personalities](plans/indexing-personalities.md).

Radiology detects projects, runs batch SCIP generators outside the UI process, caches successful data, and reports **No Index**, **Indexing**, **Current**, **Possibly Stale**, **Failed**, or **Partial**. A stale cached index remains usable while refresh runs. Indexing failures do not block browsing.

| Project evidence | Indexer | Installation behavior |
| --- | --- | --- |
| `Cargo.toml` | `rust-analyzer scip` | Radiology can run `rustup component add rust-analyzer` when `rustup` exists |
| `go.mod` | `scip-go` 0.2.7 | Radiology can install with Go into its private tools directory |
| `tsconfig.json` / JS/TS `package.json` | `scip-typescript` 0.4.0 | Radiology can install with Node/npm; project dependencies are still needed |
| Python project markers | `scip-python` 0.6.6 | Radiology can install with Node/npm; Python 3.10+ is required |
| C/C++ sources or `compile_commands.json` | `scip-clang` 0.4.0 | Automatic best-effort defaults without a database; managed Apple Silicon binary with pinned checksum; manual discovery on Intel |
| Gradle settings/build files + `.kt` / `.java` | Kotlin SCIP (`scip-java`, pinned compiler plugin) | Requires JDK 17+; managed tool build in Application Support. Supports AGP 9 built-in Kotlin; compiles an isolated copy of the real build |

Kotlin compiler indexing provides caret symbol state, definition jumps, references, and symbol search, including PR **After**. PR **Before** stays syntax-only. Validated on tkos's Kotlin 2.4.20 / AGP 9.4.1 / Gradle 9.7.1 build. Compilation can take a few minutes initially. Failed modules preserve real compiler data from successful modules as **Partial**, including after cache reload/reuse. Generated build files outside the source snapshot never become navigable destinations. Gradle uses the project's actual build steps and dependencies; project outputs go into a disposable copy and tracked inputs are checked before and after compilation. Kotlin scripts, non-JVM targets, and other compiler versions have no new compatibility claim. See [the Kotlin support contract](plans/kotlin-semantic-indexing.md).

Swift has no semantic indexer adapter. `rust-analyzer scip` remains a batch index generator rather than a persistent LSP backend.

Generated indexes and metadata live outside the repository at `~/Library/Caches/Radiology/repositories/<repository-id>/`. Pull request data lives beside them: `review.git` (bare objects, alternates to the attached repository), and `revisions/<sha>/` with the head `tree/` worktree, on-demand Before `files/`, and that revision's `index/`. Provisioned executables and per-run support files live at `~/Library/Application Support/Radiology/tools/`. Critical Lens marks live at `~/Library/Application Support/Radiology/overrides/<repository-id>.json`.

Radiology discovers at most 32 project strategies, shallowest first, and explicitly reports skipped projects. Independent project failures preserve successful indexes. A degraded Rust source-only result remains **Partial**, never **Current**.

## Development launch and diagnostics

```sh
"build/Marin Viewer.app/Contents/MacOS/Marin Viewer" \
  --repository /absolute/path/to/repository \
  --file relative/path/to/file.rs

"build/Marin Viewer.app/Contents/MacOS/Marin Viewer" \
  --repository /absolute/path/to/repository --pull-request 724

"build/Marin Viewer.app/Contents/MacOS/Marin Viewer" --verify-resources
```

`--repository PATH` opens a folder, `--file RELATIVE_PATH` selects a file inside it (in After when combined with `--pull-request N`, which opens that pull request), and `--verify-resources` compiles every bundled grammar/query combination and exits before opening a window.

For problems:

- Open the index-status popover for indexer name/version, command, exit status, bounded diagnostic head/tail, missing-file reports, Reindex, Cancel, and Install actions.
- If repository search is unavailable, install `rg`; Finder launches also check the build-recorded path and standard Homebrew/PATH locations.
- If an index is Possibly Stale, use Reindex. Partial may still provide useful intra-crate navigation.
- Python indexing needs Python 3.10+ even if its npm package installs. C/C++ automatically indexes with best-effort GNU C/C++ defaults and inferred include paths when no compilation database exists. A real `compile_commands.json` improves coverage and takes priority, including common build directories hidden from Files. Missing defines/headers, custom source preprocessors and upstream `extern "C"` gaps remain visible limitations; see [best-effort indexing](plans/clang-best-effort.md).
- Tree-sitter failures degrade to plain text or partial structure. Unsupported languages never gain semantic behavior by textual guessing.
- The local bundle is ad-hoc signed and intentionally not App Sandbox enabled because it launches Git, ripgrep, and indexers.

## Honest limitations

- Read-only: no editing, refactoring, LSP sessions, filesystem watching, or language injection.
- Pull request review indexes After only; Before is syntax-only. Mixed reused/regenerated index runs are Partial. The first review after upgrading regenerates projects whose files differ from the merge base until a format-3 index exists; Cmd-P was reassigned from the file picker alias to Open Pull Request. Fork pull requests rely on GitHub serving the head commit by SHA (with `refs/pull/N/head` as the fallback); a head that moved after listing is refused rather than substituted.
- Hide Tests is conservative and syntactic. It does not detect Python doctests, `__main__` runners or non-pytest naming styles. It also misses JS/TS tests inside functions or behind custom wrappers, and inline tests in Go/Swift (Go test functions only exist in `_test.go` files, which are hidden as files). Path rules match exact components and names, never substrings. Copy across a hidden region copies the hidden source too, just as copy across a fold does.
- Parsing is whole-file and fold state is session-local. Some grammar constructs (notably Go grouped declarations/interfaces and JSX elements) have no fold capture.
- SCIP quality is bounded by project manifests, installed tools, dependencies, cfg/features, and each indexer's behavior. Multiple definitions default to the first, with alternatives shown in the inspector.
- Locked occurrence fallback is deliberately spelling-based within one parsed function and includes shadowed locals; semantic navigation remains SCIP-only.
- The large-file fold optimization has an isolated real-source TextKit benchmark, but its recorded numbers are not a full-app pointer latency guarantee on other machines.
- Dark-mode pin colors follow a deterministic appearance-aware path but were not visually verified in the recorded development round.

## Documentation

Start with [PLAN.md](PLAN.md) and [PROGRESS.md](PROGRESS.md). Then use:

- [Development history](plans/development-history.md) — chronological requests, changes, bugs, acceptance, and historical evidence
- [Future-agent handoff](plans/agent-handoff.md) — current state, architecture, invariants, entry points, validation, and pitfalls
- [Source filters](plans/source-filters.md) — Hide Tests and Source Files Only: rules, detection, presentation, limits
- [Architecture](plans/architecture.md), [design system](plans/design-system.md), and [build system](plans/build-system.md)
- [Tree-sitter](plans/tree-sitter.md), [structural navigation](plans/structural-navigation.md), [SCIP](plans/scip-semantic-navigation.md), and [quick file picker](plans/quick-file-picker.md)
- [Grammar scanner provenance](Sources/GrammarScanners/PROVENANCE.md)
