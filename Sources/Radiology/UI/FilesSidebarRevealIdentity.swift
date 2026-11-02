import Foundation

/// Navigation and presentation changes reveal the file; ordinary caret,
/// viewport and manual folder changes do not force the list to scroll again.
struct FilesSidebarRevealIdentity: Equatable {
    let root: URL
    let path: String?
    let loadedPath: String?
    let navigation: Int
    let query: String
    let filters: SourceFilters
}
