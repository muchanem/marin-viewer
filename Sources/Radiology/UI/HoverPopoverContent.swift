import Observation

/// Updating results preserves the hosting view and its pointer tracking.
@Observable @MainActor
final class HoverPopoverContent {
    var presentation: CriticalSummaryModel.HoverPresentation

    init(_ presentation: CriticalSummaryModel.HoverPresentation) {
        self.presentation = presentation
    }
}
