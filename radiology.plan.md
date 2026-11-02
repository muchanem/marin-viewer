# Native macOS Code Browser — Strawman Plan

## Goal

Build a native macOS application optimized for **reading unfamiliar code**, especially large quantities of agent-generated code.

This is not an editor.

The first version should answer these questions very well:

- What files are in this repository?
- What is in this file?
- Where is this symbol defined?
- Where is this symbol referenced?
- What symbols exist with a given name?
- Where does this text occur?
- What is the structural shape of this file?
- How do I move rapidly through the code without losing my place?

The initial implementation will use:

- **Tree-sitter** for parsing and syntax structure
- **Tree-sitter highlighting queries** for syntax highlighting
- **ripgrep** for full-text search
- **SCIP** for cross-reference and symbol information
- **Git** only as a repository/file-discovery primitive initially; richer Git integration comes later

Do not introduce LSPs in v1.

---

# Product Principles

## Reading first

The application is optimized for:

- navigation
- orientation
- search
- folding
- symbol relationships
- maintaining context while traversing code

Editing is explicitly out of scope.

## Immediate usefulness without semantic indexing

Opening a repository must work immediately.

Tree-sitter and ripgrep should become usable before any SCIP index exists.

SCIP enriches the repository when available.

## Graceful degradation

A repository can have:

1. Tree-sitter support + SCIP
2. Tree-sitter support only
3. Plain text only

Every level should remain usable.

## Repository state is disposable

Derived indexes and parse state can always be regenerated.

The application should keep little or no important state inside the source repository.

---

# Initial UX

Use a conventional three-pane layout:

```text
┌─────────────────┬────────────────────────────────────────┬─────────────────┐
│                 │                                        │                 │
│   Repository    │              Source                    │    Inspector    │
│                 │                                        │                 │
│                 │                                        │                 │
│                 │                                        │                 │
└─────────────────┴────────────────────────────────────────┴─────────────────┘
```

The inspector may initially be hidden by default.

## Repository pane

Initially supports:

- file tree
- filename filtering
- repository-wide symbol search
- repository-wide text search

Potential presentation:

```text
FILES
  Sources/
    HTTP/
      Server.swift
      Request.swift

SYMBOLS
  HTTPServer
  HTTPRequest
  handleRequest

SEARCH
  "authorize("
```

These can be separate modes rather than simultaneously visible.

## Source pane

Supports:

- syntax highlighting
- line numbers
- current-line indication
- structural folding
- symbol breadcrumbs
- definition/reference navigation
- selection
- copy
- Cmd-click symbol navigation

No text editing.

## Inspector

When a symbol is selected:

```text
HTTPRequest.handle()

Defined:
    Sources/HTTP/Request.swift:81

References:
    Server.swift:143
    Router.swift:77
    RequestTests.swift:201
```

Later this becomes substantially richer.

---

# Architecture

Prefer a small number of explicit subsystems.

```text
Application
    │
    ├── Repository
    │      ├── file discovery
    │      ├── ignore handling
    │      └── repository metadata
    │
    ├── SourceStore
    │      ├── source buffers
    │      ├── line maps
    │      └── file identity
    │
    ├── Syntax
    │      ├── Tree-sitter parsers
    │      ├── highlighting
    │      ├── folds
    │      └── document symbols
    │
    ├── Search
    │      └── ripgrep
    │
    ├── SemanticIndex
    │      └── SCIP
    │
    └── UI
           ├── repository browser
           ├── source viewer
           ├── search results
           └── symbol inspector
```

Avoid a generic plugin architecture until multiple real implementations require it.

---

# Technology

## Application

- Swift
- AppKit
- SwiftUI where convenient for peripheral UI
- AppKit/TextKit for the central source viewer

The source viewer is important enough that its rendering and interaction should not depend on SwiftUI's text controls.

## Persistence

Use SQLite for application metadata if/when persistent storage becomes necessary.

Do not initially copy SCIP into another database unless performance or query ergonomics require it.

Cache directories should live under the normal macOS Application Support/Caches locations.

---

# Source Model

Every opened file gets a `SourceBuffer`.

Conceptually:

```swift
struct SourceBuffer {
    let fileID: FileID
    let url: URL
    let data: Data

    let lineStarts: [Int]
}
```

Internal source locations should use byte offsets.

```swift
struct SourceRange {
    let fileID: FileID
    let startByte: Int
    let endByte: Int
}
```

Build explicit conversions between:

- byte offsets
- line/column
- UTF-16 `NSRange`

Do not allow individual subsystems to invent their own canonical coordinate systems.

---

# Repository Discovery

Opening a repository should:

1. locate the repository root
2. enumerate candidate source files
3. respect `.gitignore`
4. classify files by language
5. populate the file tree
6. begin parsing visible/recently relevant files

Use Git where practical for repository discovery:

```sh
git ls-files --cached --others --exclude-standard
```

This gives us correct ignore semantics essentially for free.

Repositories that are not Git repositories should fall back to filesystem enumeration.

Exclude obviously irrelevant directories such as:

```text
.git
node_modules
vendor
build
dist
DerivedData
target
```

unless explicitly included.

---

# Language Registry

Maintain a simple registry:

```swift
struct LanguageDefinition {
    let name: String
    let extensions: [String]

    let parser: TreeSitterLanguage?
    let highlightsQuery: String?
    let foldsQuery: String?
    let symbolsQuery: String?
}
```

Initially support a handful of languages we care about rather than trying to support everything.

Suggested starting set:

- Swift
- Go
- Rust
- Python
- JavaScript
- TypeScript
- C
- C++

Adding a Tree-sitter grammar should be straightforward and isolated.

---

# Tree-sitter Integration

Tree-sitter provides the application's structural understanding of individual files.

Each parsed file maintains:

```text
SourceBuffer
    │
    └── Tree-sitter Tree
```

## Parsing

Parse files:

- when initially displayed
- when needed for search/navigation presentation
- lazily otherwise

Since v1 is read-only, source buffers are immutable until filesystem changes occur.

If a file changes on disk:

1. discard the old parse tree
2. reload the file
3. reparse it

Incremental editing support is unnecessary initially.

## Syntax highlighting

Use standard Tree-sitter highlight queries where possible.

Translate captures such as:

```text
@keyword
@string
@comment
@function
@type
@variable
@constant
```

into application-level semantic styles.

Do not hard-code colors in language integrations.

Instead map:

```text
Tree-sitter capture
        ↓
HighlightRole
        ↓
Theme
        ↓
NSAttributedString attributes
```

Example:

```swift
enum HighlightRole {
    case comment
    case keyword
    case string
    case number
    case type
    case function
    case variable
    case property
    case constant
}
```

## Folding

Derive foldable ranges from Tree-sitter.

Initial folding targets:

- function bodies
- methods
- classes/types
- namespaces/modules
- compound statements
- large literals where appropriate
- comment blocks

Store folds structurally rather than by line number.

Example:

```swift
struct Fold {
    let range: SourceRange
    let kind: FoldKind
}
```

## Document structure

Use Tree-sitter queries to extract lightweight symbols when SCIP is absent:

- class
- struct
- enum
- function
- method
- interface/protocol
- constant

This powers:

- file outline
- breadcrumbs
- structural navigation

This is explicitly syntactic, not semantic.

---

# SCIP Integration

SCIP provides repository-level semantic relationships.

Treat a SCIP index as optional.

## Loading

Look for known index locations or allow the user to choose one.

Potential convention:

```text
.scip/index.scip
index.scip
```

Later we can invoke indexers automatically.

Not initially required.

## Internal model

Normalize SCIP data into a thin application abstraction:

```swift
struct Symbol {
    let id: SymbolID
    let displayName: String
    let kind: SymbolKind?
}

struct Occurrence {
    let symbol: SymbolID
    let range: SourceRange
    let roles: OccurrenceRole
}
```

Core relationships required for v1:

- definition of symbol
- references to symbol
- symbol at source location
- repository symbol lookup

Avoid implementing every SCIP feature immediately.

## Navigation

Cmd-click behavior:

1. determine source location
2. query SCIP for the symbol at that location
3. find its definition
4. navigate there

If no SCIP information exists:

- attempt Tree-sitter-local navigation where trivial
- otherwise do nothing

## References

A references command should show:

```text
References to Foo.bar

Sources/Server.swift
  117   foo.bar()

Sources/Worker.swift
   91   foo.bar()

Tests/FooTests.swift
  143   subject.bar()
```

Selecting a result navigates to it.

---

# ripgrep Integration

Do not reimplement full-text search.

Spawn `rg`.

Example:

```sh
rg \
  --json \
  --line-number \
  --column \
  --hidden \
  --glob '!.git/*' \
  PATTERN \
  ROOT
```

Consume JSON output incrementally.

## Search UX

Cmd-Shift-F opens repository search.

Results appear as:

```text
authorize

Sources/Auth.swift
  41  func authorize(...)
  87      authorize(request)

Sources/Server.swift
  53      auth.authorize(req)
```

Support:

- literal search
- regex search
- case sensitivity toggle
- include/exclude glob

Search should stream results as ripgrep produces them.

Do not wait for the subprocess to exit before displaying matches.

## File search

Filename search does not need ripgrep.

Use the repository's known file list.

Fuzzy matching can initially use a simple scorer.

---

# Source Viewer

This is the core UI component.

Implement as an AppKit view backed by TextKit.

Requirements:

- efficient display of large files
- line numbers
- syntax highlighting
- selection
- copy
- folding
- symbol hit testing
- clickable references
- visible current location
- scroll-position restoration

The source viewer is read-only.

Avoid pretending an editor component is necessary if a simpler text-layout implementation performs better.

## Rendering pipeline

Conceptually:

```text
SourceBuffer
    │
    ├── Tree-sitter highlights
    ├── folds
    └── SCIP symbol ranges
            │
            ▼
    presentation model
            │
            ▼
       TextKit layout
```

Syntax highlighting should be applied asynchronously.

Opening a file must display plain text immediately.

Highlighting can appear afterward.

---

# Folding UX

Folding is a first-class feature, not editor compatibility baggage.

Initial commands:

```text
Fold
Fold All
Unfold
Unfold All
Fold to Definitions
```

`Fold to Definitions` is important.

For example:

```swift
struct HTTPServer {
    let listener: Listener
    let router: Router

    func start() { … }

    func handle(_ request: Request) -> Response { … }

    func shutdown() { … }
}
```

This should provide an immediate structural overview of a large file.

Later this becomes "skeleton mode."

---

# Navigation

Maintain explicit navigation history.

```swift
struct Location {
    let fileID: FileID
    let byteOffset: Int
}
```

Commands:

```text
Go Back
Go Forward
Go to Definition
Find References
Go to Symbol
Go to File
```

Opening a definition must push the current location onto history.

Back/forward should behave like a browser, not like switching editor tabs.

## Tabs

Avoid tabs initially.

Use one primary navigation surface with browser-style history.

If multiple persistent views are eventually necessary, add them based on observed use rather than editor convention.

---

# Symbol Search

Provide Cmd-T or equivalent for repository symbol search.

Data source priority:

1. SCIP
2. Tree-sitter-derived document symbols

SCIP search can initially be basic substring/fuzzy matching over known symbol names.

Example:

```text
> auth req

authorizeRequest
HTTPRequestAuthorization
AuthRequest
```

Selecting the symbol navigates to its definition.

---

# File Outline

Each source file should have an outline derived from Tree-sitter:

```text
HTTPServer
  init()
  start()
  accept()
  handleRequest()
  shutdown()

HTTPRequest

HTTPResponse
```

Selecting an item scrolls to it.

This can initially live in the inspector or repository sidebar.

---

# Breadcrumbs

At the top of the source viewer:

```text
Sources > HTTP > Server.swift > HTTPServer > handleRequest()
```

Tree-sitter supplies lexical containment.

SCIP is not required.

Each breadcrumb component is clickable.

---

# Keyboard Model

The application should be extremely keyboard-friendly.

Strawman bindings:

```text
Cmd-P           Go to file
Cmd-T           Go to symbol
Cmd-Shift-F     Search repository
Cmd-click       Go to definition
Shift-Cmd-G     Find references

Cmd-[           Back
Cmd-]           Forward

Cmd-L           Go to line

Cmd-Option-[    Fold
Cmd-Option-]    Unfold
```

Exact bindings can change later.

---

# Concurrency

Repository work should happen off the main thread.

Use Swift structured concurrency.

Potential actor boundaries:

```text
RepositoryActor
TreeSitterActor
SCIPActor
SearchActor
```

Do not serialize unrelated parsing work unnecessarily.

Prioritize:

1. currently visible file
2. navigation destination
3. files shown in search results
4. everything else

---

# Caching

Cache:

- Tree-sitter parse-derived metadata
- highlighting spans
- fold ranges
- document symbols
- parsed SCIP representation if useful

Cache keys should include:

```text
repository identity
file path
file content hash
grammar version
query version
```

Do not make correctness depend on caches.

---

# File Watching

Use filesystem notifications to detect repository changes.

When a file changes:

1. invalidate its `SourceBuffer`
2. invalidate parse/highlight/fold state
3. reload it if visible
4. invalidate relevant semantic data if necessary

If the SCIP index changes, reload it.

SCIP does not need to remain perfectly synchronized in v1.

A visible "semantic index may be stale" state is acceptable.

---

# Error Handling

Subsystem failures should remain local.

Examples:

- malformed Tree-sitter query:
  - disable that language feature
  - still display file

- ripgrep unavailable:
  - repository still opens
  - disable repository text search

- SCIP unavailable:
  - syntax/navigation features still work

- unsupported language:
  - display plain text

The application should almost never refuse to open source code.

---

# Initial Milestones

## Milestone 1 — Source viewer

Deliver:

- native macOS application
- open repository
- file tree
- open file
- source display
- line numbers
- scroll restoration

No Tree-sitter yet.

Success criterion:

> It is already pleasant to browse a repository.

---

## Milestone 2 — Tree-sitter

Deliver:

- language detection
- parsing
- syntax highlighting
- file outline
- breadcrumbs
- folding

Success criterion:

> Opening a source file immediately exposes its structure.

---

## Milestone 3 — Search

Deliver:

- Cmd-P filename search
- repository ripgrep search
- streaming result display
- navigation from result to source

Success criterion:

> Finding arbitrary code is faster than opening the repository in an editor.

---

## Milestone 4 — SCIP

Deliver:

- SCIP index loading
- symbol-under-cursor lookup
- go to definition
- find references
- repository symbol search

Success criterion:

> Cross-file exploration works without running a language server.

---

## Milestone 5 — Reader UX

Polish the features that make this a browser rather than a weak editor:

- excellent back/forward navigation
- fold-to-definitions
- structural outline
- symbol inspector
- keyboard navigation
- source-position preservation
- fast transitions between definitions and references

Success criterion:

> Reading a large unfamiliar subsystem feels materially better than VS Code/Xcode.

---

# Explicitly Deferred

Do not build these yet:

- editing
- save
- LSP integration
- completion
- diagnostics
- compiler invocation
- debugging
- terminal
- Git diff UI
- blame
- semantic diff
- embeddings
- LLM integration
- call hierarchy
- control-flow analysis
- dataflow analysis
- automatic SCIP generation
- remote repositories
- collaborative features
- extension/plugin architecture

Some of these are important.

None are necessary to validate the core product.

---

# First Vertical Slice

The first meaningful end-to-end version should support one language extremely well.

Use Swift or Go.

The slice:

1. open repository
2. display files
3. open source
4. Tree-sitter highlight source
5. show structural outline
6. fold function bodies
7. Cmd-P to another file
8. Cmd-Shift-F through ripgrep
9. load an existing SCIP index
10. Cmd-click a symbol
11. jump to its definition
12. Cmd-[ to return

That is enough application to start using it on itself.

---

# Open Questions

Do not resolve these architecturally until implementation forces the issue.

## Text rendering

Should the source surface use:

- `NSTextView`
- lower-level TextKit 2
- a custom renderer

Start with `NSTextView`/TextKit and measure.

## SCIP storage

Should we:

- query decoded SCIP directly
- normalize it into memory
- import it into SQLite

Start with the least machinery that works.

## Tree-sitter integration

Options include:

- direct C API bridging
- an existing Swift wrapper

Prefer direct bindings if wrappers substantially constrain query/tree access.

## Repository identity

Need a durable way to recognize the same repository across launches.

Likely based on canonical path initially.

## Huge repositories

Do we ever proactively parse every file?

Probably not.

Start lazy and add background indexing only when an actual feature requires it.

---

# Definition of v1

Version 1 is successful if I can point it at a large repository and spend an hour reading code without wishing I had opened VS Code.

Specifically:

- source opens instantly
- highlighting is accurate
- folding exposes structure
- file search is immediate
- text search is immediate
- definitions and references work when SCIP exists
- navigation history keeps me oriented
- the UI remains focused on reading rather than editing

Everything after that should be driven by deficiencies encountered while using it to review real agent-generated code.
