import AppKit
import SwiftUI

/// Native tracking covers the entire popover, including padding and buttons,
/// independently of SwiftUI child replacement and the source's key window.
@MainActor
final class HoverPopoverHost: NSHostingController<CriticalHoverView> {
    let content: HoverPopoverContent
    private let hovered: (Bool) -> Void

    init(presentation: CriticalSummaryModel.HoverPresentation,
         navigate: @escaping (SemanticPosition?, String) -> Void,
         hovered: @escaping (Bool) -> Void) {
        content = HoverPopoverContent(presentation)
        self.hovered = hovered
        super.init(rootView: CriticalHoverView(content: content, navigate: navigate))
        sizingOptions = [.preferredContentSize]
        view.addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(presentation:navigate:hovered:)") }

    override func mouseEntered(with event: NSEvent) { hovered(true) }
    override func mouseExited(with event: NSEvent) { hovered(false) }
}
