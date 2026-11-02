import AppKit

/// A separate gutter never changes TextKit's horizontal document coordinates.
final class SourceContainerView: NSView {
    let scroll = SourceScrollView()
    var gutter: LineNumberGutter?
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { true }
    override func layout() {
        super.layout()
        gutter?.frame = NSRect(x: 0, y: 0, width: Theme.gutterWidth, height: bounds.height)
        scroll.frame = NSRect(x: Theme.gutterWidth, y: 0, width: max(0, bounds.width - Theme.gutterWidth), height: bounds.height)
    }
}
