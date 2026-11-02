import Foundation
import Observation
import ViewerCore

/// Per-window viewer state. The main window owns the strip, the sidebars and the panel; a
/// secondary window is a reader with no strip or sidebar, whose questions go to the main
/// window's session until "Promote to Session" forks one for it.
@Observable @MainActor
final class ViewerWindowModel: Identifiable {
    enum Kind: Equatable, Sendable { case main, secondary }

    enum PanelTab: String, CaseIterable, Identifiable, Sendable {
        case session = "Session"
        case notes = "Review notes"
        case context = "Context"
        var id: Self { self }
    }

    let id = UUID()
    let kind: Kind
    /// The right panel (⌥⌘I). In the main window it starts open.
    var isPanelPresented: Bool
    var panelTab: PanelTab = .session
    /// A promoted secondary window's own session; nil means the store's main session.
    var ownSession: ViewerSession?
    /// The step diagram the "Inside this PR" card is zoomed into.
    var zoomedStep: Int?
    /// The PR description card's open layer: 1, 2 or 3.
    var descriptionLevel = 1
    /// The diagram shown in the larger sheet, for diagrams that overflow their card.
    var enlargedDiagram: DiagramKey?
    /// The file, step, box or note the reader last clicked: ⌘> asks about it when nothing with
    /// keyboard focus offers a chip.
    var lastAskTarget: Chip?
    var isPostConfirmationPresented = false
    /// File > Open PR….
    var isOpenPRPresented = false
    /// The window's reader, for chips from its caret and for the Context tab.
    @ObservationIgnored weak var reader: AppModel?

    init(kind: Kind, reader: AppModel? = nil) {
        self.kind = kind
        self.reader = reader
        isPanelPresented = kind == .main
    }

    /// Escape zooms the PR map back out.
    func zoomOut() { zoomedStep = nil }
}

/// What a secondary code window opens: a file of the Marin checkout, at a line.
struct CodeWindowRequest: Codable, Hashable, Sendable {
    var path: String
    var line: Int?
    /// The PR head worktree when one is ready, else the Marin clone.
    var root: String
}
