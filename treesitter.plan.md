# Next Step: Tree-sitter Source Structure

## Goal

Make the source viewer structurally aware.

After this step, opening a supported source file should provide:

- syntax highlighting
- identification of declarations and scopes
- foldable functions/types/blocks
- an outline of the current file
- enough source mapping to support later SCIP navigation

Do not add SCIP yet.

## 1. Integrate Tree-sitter

Add Tree-sitter to the app and support one language first: Swift.

Create a small abstraction:

```swift
protocol SourceLanguage {
    var treeSitterLanguage: OpaquePointer { get }

    func highlights(in tree: Tree) -> [Highlight]
    func folds(in tree: Tree) -> [Fold]
    func symbols(in tree: Tree) -> [DocumentSymbol]
}