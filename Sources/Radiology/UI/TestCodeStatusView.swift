import SwiftUI

/// Reader footer note while Hide Tests is on: how many test regions this
/// file hides, or that an explicitly opened test file is shown in full.
struct TestCodeStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.sourceFilters.hidesTests, model.source != nil {
            if model.isTestDocument {
                Text("·").accessibilityHidden(true)
                Label("Test file", systemImage: "testtube.2")
                    .help("Hide Tests keeps a test file you open readable in full; it hides test files in the Files sidebar and test code inside other files.")
            } else if let hidden = model.testCodePresentation?.hiddenRegions.count, hidden > 0 {
                Text("·").accessibilityHidden(true)
                Text("^[\(hidden) test region](inflect: true) hidden")
                    .help("Click a region's label or gutter control to show it, or turn off Hide Tests (⌃⌘T).")
            }
        }
    }
}
