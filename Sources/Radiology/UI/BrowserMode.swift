enum BrowserMode: String, CaseIterable, Identifiable {
    case changes = "Changes"
    case files = "Files"
    case codePaths = "Code Paths"
    case search = "Search"
    /// The viewer's numbered code path for an open wordbase PR.
    case steps = "Code path"
    var id: Self { self }

    /// Changes exists only while a pull request is under review.
    static func available(reviewing: Bool) -> [BrowserMode] {
        reviewing ? [.changes, .files, .codePaths, .search] : [.files, .codePaths, .search]
    }

    /// With a wordbase PR open, the sidebar leads with its code path (DESIGN.md §2).
    static func available(reviewing: Bool, viewerPR: Bool) -> [BrowserMode] {
        viewerPR ? [.steps, .changes, .files, .search] : available(reviewing: reviewing)
    }

    var systemImage: String {
        switch self {
        case .changes: "doc.text"
        case .files: "folder"
        case .codePaths: "point.topleft.down.to.point.bottomright.curvepath"
        case .search: "magnifyingglass"
        case .steps: "list.number"
        }
    }
}
