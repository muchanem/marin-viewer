enum BrowserMode: String, CaseIterable, Identifiable {
    case changes = "Changes"
    case files = "Files"
    case codePaths = "Code Paths"
    case search = "Search"
    var id: Self { self }

    /// Changes exists only while a pull request is under review.
    static func available(reviewing: Bool) -> [BrowserMode] {
        reviewing ? allCases : [.files, .codePaths, .search]
    }

    var systemImage: String {
        switch self {
        case .changes: "doc.text"
        case .files: "folder"
        case .codePaths: "point.topleft.down.to.point.bottomright.curvepath"
        case .search: "magnifyingglass"
        }
    }
}
