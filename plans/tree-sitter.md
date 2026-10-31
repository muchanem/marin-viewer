# Tree-sitter integration

Radiology parses source structure with real native Tree-sitter grammars; this
subsystem has no regex-based parser substitute and no language server.
App-level SCIP support is a separate, later layer documented in
`plans/scip-semantic-navigation.md`. Unsupported files are shown as plain text.

## Supported languages

| Language | Extensions | Grammar | Pinned version | Query directories |
| --- | --- | --- | --- | --- |
| Swift | `.swift` | [alex-pinkus/tree-sitter-swift](https://github.com/alex-pinkus/tree-sitter-swift) | `0.7.3-with-generated-files` | `swift` |
| Rust | `.rs` | [tree-sitter/tree-sitter-rust](https://github.com/tree-sitter/tree-sitter-rust) | `0.24.2` | `rust` |
| Go | `.go` | [tree-sitter/tree-sitter-go](https://github.com/tree-sitter/tree-sitter-go) | `0.25.0` | `go` |
| Python | `.py`, `.pyi` | [tree-sitter/tree-sitter-python](https://github.com/tree-sitter/tree-sitter-python) | `0.25.0` | `python` |
| JavaScript / JSX | `.js`, `.jsx`, `.mjs`, `.cjs` | [tree-sitter/tree-sitter-javascript](https://github.com/tree-sitter/tree-sitter-javascript) | `0.25.0` | `ecmascript` + `javascript` + `jsx` |
| TypeScript | `.ts`, `.mts`, `.cts` | [tree-sitter/tree-sitter-typescript](https://github.com/tree-sitter/tree-sitter-typescript) (`typescript`) | `0.23.2` | `ecmascript` + `typescript` |
| TypeScript JSX | `.tsx` | the same package's `tsx` grammar | `0.23.2` | `ecmascript` + `typescript` + `jsx` |
| Kotlin | `.kt`, `.kts` | [fwcd/tree-sitter-kotlin](https://github.com/fwcd/tree-sitter-kotlin) | `0.3.8` | `kotlin` |
| C | `.c` | [tree-sitter/tree-sitter-c](https://github.com/tree-sitter/tree-sitter-c) | `0.24.2` | `c` |
| C++ | `.C`, `.cc`, `.cpp`, `.cxx`, `.c++`, `.h`, `.hh`, `.hpp`, `.hxx`, `.h++`, `.ipp`, `.inl`, `.tpp`, `.tcc` | [tree-sitter/tree-sitter-cpp](https://github.com/tree-sitter/tree-sitter-cpp) | `0.23.4` | `c` + `cpp` |

Plain `.h` uses C++ to retain class/template structure in mixed headers;
uppercase `.C` is the deliberate case-sensitive C++ exception. Both grammars
provide all five query roles. Recursive declarator handling selects exact
names rather than return types/parameters. See [C/C++ support](c-cpp-support.md).

JSX and TSX are separate languages, not supersets: the TypeScript grammar
rejects JSX, and the TSX grammar reads `<T>expr` as an element rather than a
type assertion. Radiology therefore routes `.tsx` to its own grammar, and
`SyntaxLanguageTests.jsxAndTsxNeedTheirOwnGrammars` locks that behaviour in.
The JavaScript grammar handles JSX natively, so `.js` and `.jsx` share it.

Grammars are resolved by SwiftPM, compiled from upstream's committed generated
C, and linked statically; `Package.resolved` locks the whole graph. All
grammars report Tree-sitter ABI 14 or 15, inside the 0.25 runtime's supported
range. Every grammar listed above is MIT-licensed.

## Vendored sources

Two things are vendored, each with provenance recorded next to the files:

- `Sources/GrammarScanners` — the external scanners for JavaScript and Python.
  Upstream's SwiftPM manifests probe for `src/scanner.c` with a path relative to
  the manifest process, so the scanners are never compiled and the grammars fail
  to link. See `Sources/GrammarScanners/PROVENANCE.md`.
- `Sources/Radiology/Queries` — Radiology's own `.scm` queries. They are written
  against each grammar's `src/node-types.json` and informed by the upstream
  `queries/highlights.scm` of the same pinned version; each file names its
  source and licence in a header comment. The Kotlin file follows fwcd's query,
  which derives from nvim-treesitter (Apache-2.0).

Upstream query bundles also ship inside each grammar's own SwiftPM resource
bundle. Radiology does not read them: they cover highlighting only, use capture
vocabularies that differ per grammar, and carry predicates Radiology would have
to interpret differently.

## Queries

Each language supplies four roles — `highlights`, `folds`, `symbols`, `scopes` —
as `Queries/<directory>/<role>.scm`, packaged as SwiftPM resources of the
`Radiology` target and read through `Bundle.module`. A language may list several
directories; `SyntaxQueryLoader` concatenates them in order, which lets TSX reuse
the shared ECMAScript core plus the TypeScript and JSX overlays instead of
duplicating them. Only node types present in every grammar that uses it may
appear in a shared directory.

Capture vocabulary, shared across languages and mapped centrally in
`Theme.SyntaxColors`:

- `comment`, `comment.documentation`
- `string`, `string.escape`, `string.special`
- `number`, `constant`, `constant.builtin`
- `keyword` and the `keyword.{function,return,import,conditional,repeat,modifier,exception,coroutine,operator,type}` refinements
- `type`, `type.builtin`, `constructor`, `namespace`, `tag`
- `function`, `function.call`, `function.method`, `function.macro`, `function.builtin`
- `property`, `attribute`, `label`, `variable.builtin`, `variable.parameter`

Captures prefixed with `_` are helpers for predicates and are never painted.
Highlights are returned in paint order — widest span first at a given start,
then query order — so a nested or later pattern colours over a broader earlier
one. Within a file, general patterns are written first and specific ones last.

Fold captures use `fold.{function,type,block,comment,imports}` and symbol
captures `symbol.<kind>` paired with a `@name` capture. When several patterns
capture the same node, `SyntaxWorker` keeps the most specific kind.

Fold queries capture only delimiter-wrapped nodes wherever the grammar has one,
because a collapsed brace body should still read as `{}`. Where a language has
no such node — Python blocks, Kotlin `statements`, Swift `statements` — the
renderer hides the captured range whole instead of stranding its first
character.

### Predicates

`#eq?`, `#not-eq?`, `#any-of?`, `#not-any-of?`, `#match?`, and `#not-match?` are
evaluated by `SyntaxWorker`. SwiftTreeSitter's own `QueryMatch.allowed(in:)`
cannot be used: it resolves predicate text through `Node.range`, which assumes
UTF-16 input, and Radiology parses UTF-8. Predicates are therefore evaluated
against the canonical byte ranges. `#set!` is metadata and never filters;
`#is-not? local` needs name resolution Radiology does not have, so it never
filters either, and Radiology's own queries avoid it.

## Test-region detection

`SyntaxWorker` also runs `TestRegionDetector` (Rust, Kotlin, Python,
JavaScript/JSX, TypeScript, TSX) on the same tree after the query roles and
publishes `SyntaxSnapshot.testRegions` and `isTestOnlyDocument`. It walks
node shapes directly with tree cursors and an explicit stack, not `.scm`
queries. Rust `cfg` predicates need three-valued evaluation over token trees,
and TS needs file-level binding analysis, which queries cannot express. Node
shapes were confirmed by dumping the pinned grammars. Rules and limits are in
plans/source-filters.md.

## Lifecycle and coordinates

`SyntaxWorker` is an actor. Parsers, trees, and compiled queries never leave it;
compiled queries are cached per grammar for the session, because compilation is
far more expensive than a parse. It feeds Tree-sitter UTF-8 data, so every node
and query range is in the application's canonical byte coordinates. A
`SyntaxSnapshot` is `Sendable` and carries highlights, folds, symbols, scopes,
the originating language, and the root error flag.

`AppModel` publishes the `SourceBuffer` before any syntax work, so opening a file
is immediate. Cancellation plus the source generation UUID prevents a superseded
parse from colouring or populating the outline of a newer file. Unsupported
extensions return no snapshot. Ranges convert to UTF-16 only through
`SourceBuffer.utf16Range(forByteRange:)`, at the TextKit boundary.

## Failure behaviour

Source readability never depends on parsing:

- An unregistered extension yields no snapshot and plain text.
- A missing or invalid query resource throws a `BrowserError` naming the
  language, the role, and the reason. `AppModel` stores it in `syntaxError`;
  the source footer shows "Structure unavailable" with the message in its
  tooltip, and the outline shows the same message.
- Malformed source still parses: Tree-sitter error recovery returns partial
  highlights and declarations, `hasParseErrors` is set, and the footer shows
  "Partial structure".

`Radiology --verify-resources` compiles every registered grammar's queries out
of the running bundle and exits, which is how a packaged `.app` is checked
under a Finder-style launch. `build.sh` additionally fails the build if the
query resources are absent from the assembled bundle.

## Limits

- Tree-sitter symbols are syntactic, not semantic. Cross-file resolution comes
  only from the separate optional SCIP layer; there is no language server.
- Folding is session-local and resets when the file changes. Fold to Definitions
  collapses implementation bodies, while breadcrumbs use syntactic containment.
- Parses are whole-file; there are no incremental edits (the source is
  read-only) and no parse-tree cache across files.
- Go interface bodies, Go grouped `const`/`var` blocks, and JSX elements have no
  delimiter-wrapped node in their grammars, so they are not foldable.
- Indentation/body-line folds are anchored to the preceding visible signature
  by the structural-navigation layer, rather than leaving a control on a hidden
  first body line.
- Highlight coverage favours common constructs. Language injection (regex in
  JavaScript, SQL in strings, code in Markdown) is not implemented.
- `#is-not? local` is accepted but never filters, because lexical scopes are
  reported, not resolved.
- Syntax roles are distinguished by colour alone. The dynamic system palette
  adapts to light, dark, and increased contrast, but there is no non-colour
  differentiator for `accessibilityDifferentiateWithoutColor`.
