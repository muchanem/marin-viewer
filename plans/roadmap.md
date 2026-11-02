# Implementation roadmap

The original product specification is `radiology.plan.md`. Preserve its reading-first direction and explicit exclusions.

## Delivered foundation

Milestone 1: native app, repository/folder open, file tree, source loading, read-only TextKit display, line numbers, line-position restoration. Navigation history, go-to-line, recent folders, source text sizing, and manual refresh make this useful for dogfooding.

Core milestone 3 work: ordered-subsequence fuzzy quick file picker, streaming cancellable ripgrep search, literal/regex and case options, include/exclude globs, and result-to-source byte navigation.

## Delivered: Tree-sitter structure and structural navigation

Swift, Rust, Go, Python, JavaScript/JSX, TypeScript, TSX, and Kotlin all use actual Tree-sitter parsing and grammar-specific queries on a worker actor. Plain text appears first; query colors, lexical scopes, structural fold markers, and the document outline arrive asynchronously under a stale-result generation guard. Byte coordinates stay canonical. The outline reflects actual containment, source and outline synchronize without recording previews, scope breadcrumbs follow scrolling, and Fold to Definitions preserves declaration shape. Syntactic symbols are not presented as semantic identities.

## Delivered: app-owned SCIP indexing and semantic navigation

The plan changed from "load a supplied index" to "the app owns generation": Radiology inspects build files, picks indexer strategies, verifies or installs the tools, runs them in their own process group, caches `index.scip` plus freshness metadata under Caches, and decodes the protobuf itself. Symbol-under-caret, ⌘-click and menu Go to Definition with exact Back, Find References grouped by file, ⌘T ranked symbol search, a Symbol inspector, and a footer status with diagnostics are implemented. Rust was accepted against real tkos at 338/340 files; Go and TypeScript paths were exercised in later refinement. Python still requires Python 3.10+ and C/C++ requires a compilation database plus manually installed scip-clang. No LSPs. See `plans/scip-semantic-navigation.md`; `plans/scip-ui-handoff.md` is a historical first-cut checklist.

### SCIP follow-ups

Hover preview popups, a definition chooser for multi-definition symbols, filesystem-driven freshness, scip-java for Kotlin/Java, end-to-end fixtures for the Go/TypeScript/Python adapters, and a preference for automatic indexer installation.

## Reader hardening

Remaining candidates include filesystem notifications with source/parse/index invalidation, pixel-exact viewport and selection restoration, horizontal-position preservation, broader repository cancellation/streaming benchmarks, and deployment-target validation on macOS 14. Fuzzy file ranking and real large-fold profiling are delivered. Improve behavior based on actual reading sessions, not editor feature parity.

No editing, save, completion, debugging, terminal, Git diff/blame, AI features, remote repositories, or plugin framework in this phase.
