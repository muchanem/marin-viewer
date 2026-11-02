import SwiftUI

/// Keep as much nearby context as fits. Omit directories from the start of
/// the path, then outer declarations, before truncating the final component.
struct SourceBreadcrumbPath: View {
    let rootName: String
    let path: String
    let symbols: [DocumentSymbol]
    let select: (DocumentSymbol) -> Void

    var body: some View {
        let components = path.split(separator: "/").map(String.init)
        let directories = Array(components.dropLast())
        let fileName = components.last ?? path
        ViewThatFits(in: .horizontal) {
            ForEach(SourceBreadcrumbVariant.options(directoryCount: directories.count, symbolCount: symbols.count)) { variant in
                SourceBreadcrumbTrail(rootName: rootName, path: path, fileName: fileName,
                                      directories: Array(directories.dropFirst(variant.omittedDirectories)),
                                      visibleRoot: variant.showsRoot ? rootName : nil,
                                      hasOmissions: !variant.showsRoot || variant.omittedDirectories > 0 || variant.symbolCount < symbols.count,
                                      symbols: symbols, visibleSymbols: Array(symbols.suffix(variant.symbolCount)), select: select)
                    .fixedSize(horizontal: true, vertical: false)
            }
            SourceBreadcrumbTrail(rootName: rootName, path: path, fileName: fileName, hasOmissions: true,
                                  showsFile: symbols.isEmpty, symbols: symbols,
                                  visibleSymbols: Array(symbols.suffix(1)), select: select)
                .fixedSize(horizontal: true, vertical: false)
            SourceBreadcrumbTrail(rootName: rootName, path: path, fileName: fileName, hasOmissions: true,
                                  showsFile: symbols.isEmpty, symbols: symbols,
                                  visibleSymbols: Array(symbols.suffix(1)), select: select)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .help(([rootName, path] + symbols.map(\.name)).joined(separator: " / "))
    }
}
