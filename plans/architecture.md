# Architecture

The executable is `Radiology`, built directly with SwiftPM. SwiftUI owns the window, toolbar, commands, sidebar, search, and sheets. `SourceViewer` bridges the central read-only AppKit/TextKit surface using `NSViewRepresentable`; this is an explicit product requirement, not a general escape from SwiftUI.

## State and ownership

`BookmarkModel` owns a persisted ordered list for the canonical attached checkout
and optional PR number. `BookmarkStore` uses injected preferences; BookmarkResolver
reads and safely relocates saved byte/line anchors off MainActor. Bookmark jumps
preserve Before/After through the shared exact-caret history path. Two nested
native splits provide the third Context pane and independently movable dividers.
See [bookmarks.md](bookmarks.md).

`RadiologyApp` owns one `@State AppModel`, an `@Observable @MainActor` class passed through the environment. It owns repository/source/search state, canonical navigation destinations, navigation history, errors, and UI presentation. Workers do not mutate UI state.

`ReaderSessionStore` persists the last confirmed attached repository path and PR
number in injected UserDefaults. The window's one-time launch task restores that
identity through fresh repository/PR preparation, suppressing intermediate
local-mode saves. Explicit CLI/manual choices supersede startup; Exit PR saves
local mode; failed restoration retains the record for retry. Cached worktree
paths and source byte positions are never persisted across launches. See
[session restoration](session-restoration.md).

`RepositoryWorker`, `SourceStore`, `CommandRunner`, `SearchWorker`, `SyntaxWorker`, `SemanticIndexService`, `ToolProvisioner`, and `SemanticQueryWorker` are actors. Disk, parsing, and subprocess work stays outside MainActor. Tasks are cancelled when requests are superseded. Generation identifiers prevent old completions or streamed batches from replacing newer state. RunningProcess serializes launch/cancellation with a lock; it is the sole manually Sendable process wrapper.

## Repository

Git discovery uses `rev-parse --show-toplevel` and NUL-delimited `ls-files --cached --others --exclude-standard`. NUL delimiters preserve spaces and embedded newlines. Files are deduplicated, filtered for generated directories, and transformed into an explicit `FileNode` tree. Non-Git folders use relative filesystem enumeration; this avoids macOS /var versus /private/var aliases changing path slicing. Symlink directories are not traversed in the fallback. SourceStore rejects links escaping the selected root.

AppModel.fileTree remains the filtered snapshot under SourceFilters. Files uses
FilesSidebarPresentation to reveal the current document through those filters;
native disclosures/ScrollViewReader expand/select/center it without reopening
source. Snapshot/search/quick picker/indexing keep their full scope. See
[files-sidebar-navigation.md](files-sidebar-navigation.md) and source-filters.md.

## Source and coordinates

`SourceBuffer` stores UTF-8 data, immutable text, byte line starts, UTF-16 line starts, and total UTF-16 length. Navigation locations are `SourceLocation(path, byteOffset)`. Only SourceBuffer translates between byte offsets, line locations, and TextKit UTF-16 offsets. Positions inside a multi-byte scalar clamp to its start. Tests exercise emoji, CJK, combining marks, and CRLF.

UTF-8 text is supported; binary, other encodings, and files exceeding 16 MB show local errors. Every file switch reads from disk; there is no correctness-dependent cache. Refresh reloads discovery and the visible file. Automatic filesystem notifications remain pending.

## Viewer

`SourceViewer` owns the AppKit bridge; `SourceViewerCoordinator` holds delegates and bounds notifications. `ReaderTextView` provides selection, copy, native find bar, and current-line highlighting; editing and substitution are disabled. `LineNumberGutter` draws only visible line labels. The source is not soft-wrapped, with native horizontal and vertical scrolling.

Canonical positions are saved per file on scrolling/selection. An ordinary file
visit adopts that position when departed; pinned structural/search jumps do not.
File lookup and search both call `navigate(to:)`. Back/forward move a history
cursor without recording a new visit. Navigating after going back discards the
future branch. Position restoration is currently line-based, not pixel-exact,
and horizontal offsets are not persisted.

Structural navigation pins committed outline/breadcrumb/search targets in
history. Only an ordinary file-opening entry adopts its last passive scroll
position when departed; previews and synchronization never create entries.
The outline tree and breadcrumb chain derive from strict symbol-range
containment. Fold rendering keeps source bytes unchanged, and the separate
gutter omits TextKit null glyphs so hidden lines cannot overpaint labels.

Sidebar selection is view-local and synchronized with the model; programmatic navigation must never feed back into `openFile` and replace a search result's byte location.

## Search

SearchWorker launches ripgrep with JSON output. Query options are argument-array values, never shell strings. A `--` separator protects leading-dash queries. Results decode path/text fields (including base64 forms), absolute UTF-8 offsets, and individual submatches. Batches are emitted while rg runs, with 200 ms input debounce and a 5,000-result cap. stderr uses a temporary file to avoid a two-pipe deadlock. No-match exit code 1 is successful. Invalid patterns, missing tools, and other failures appear in the search pane.

Tree-sitter consumes SourceBuffer's UTF-8 bytes directly. Query results remain byte ranges until SourceBuffer converts them at the TextKit boundary. Predicates are evaluated against those same byte ranges rather than SwiftTreeSitter's UTF-16-derived `Node.range`. See `plans/tree-sitter.md`.

## Semantics

`ContextModel` owns reference disclosure and asynchronous caller-tree phases.
`ReferenceCallTreeWorker` traces incoming exact SCIP references verified against
parsed call sites, with per-request file/edge caches, path-local cycle detection,
and incremental row budgets without a depth cutoff. Boundaries preserve unknown
invocations rather than inventing edges. A native VSplitView resizes independently
scrolling References and Definition/Outline. See
[reference-call-trees.md](reference-call-trees.md).

`SemanticIndexService` owns SCIP generation per repository: it inspects build files, selects `IndexingStrategy` values from the adapter registry, loads the cached index and compares fingerprints, runs indexers through `IndexerProcess` (posix_spawn, own process group, file-backed stdout/stderr, bounded tails), decodes the protobuf with the in-tree `SCIPDecoder`, and publishes a `SemanticPublication` atomically under a generation guard. `SemanticModel` is the `@Observable @MainActor` owner of status, outcomes, the open file's `DocumentSemantics`, caret target, references, and ⌘T matches; `AppModel+Semantics` turns targets into exact-history navigation. SCIP line/column coordinates convert to canonical bytes only in `SourceBuffer` and `DocumentSemantics`, against the file as loaded, and never produce positions that do not fit the current bytes. Generated data lives in `~/Library/Caches/Radiology/repositories/<id>/`. See `plans/scip-semantic-navigation.md`.

`TraitImplementationIndexer` enriches changed indexes before publication with
exact-identity Rust impl blocks. A versioned per-file cache covers exact bytes
and semantic occurrences; stale contributions are excluded. `ContextModel` owns
`TraitImplementationsModel`; `ContextDetailPane` swaps the middle inspector's
content for trait contexts while retaining both dividers. Navigation
verify destination blobs through a separate actor and reject late results.
Trait rows are now dense direct-navigation Buttons; implementation preview
views/state/tasks have been removed.
See [rust-trait-implementations.md](rust-trait-implementations.md).

`AppModel.inspectorPanes` owns an Equatable app-wide display preference value,
persisted with guarded didSet like source filters. The inspector and View menu
share native checked controls; RootView reopens its own presentation binding on
explicit enablement. `InspectorPaneStack` composes only active regions without
resetting Context/Bookmark model state. See
[inspector-pane-controls.md](inspector-pane-controls.md).

The syntax subsystem is a small value-typed registry rather than one type per
language: `SourceLanguage` pairs a grammar with an ordered list of query
directories, `SourceLanguageRegistry` maps path extensions to it,
`SyntaxQueryLoader` reads and compiles `.scm` resources out of `Bundle.module`,
and `SyntaxWorker` owns the parsers and a per-grammar compiled-query cache.
`RepositoryFile.language` derives its label from the same registry, so there is
one source of truth for which files are parsed.
