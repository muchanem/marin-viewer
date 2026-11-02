import SwiftUI

/// The per-file Before/After picker, beside source mode in the main toolbar.
struct SourceRevisionPicker: View {
    let control: ReviewRevisionControl
    let setRevision: (ReviewRevision) -> Void
    @State private var selectedRevision: ReviewRevision = .after

    var body: some View {
        Picker("Revision", selection: $selectedRevision) {
            ForEach(ReviewRevision.allCases) { revision in
                Text(revision.title).tag(revision)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: Theme.revisionPickerWidth)
        .disabled(control.available.count < 2)
        .help(revisionHelp)
        .accessibilityLabel("Before or After the pull request")
        .accessibilityValue("\(control.current.title), \(control.status)")
        .onChange(of: control.current, initial: true) { selectedRevision = control.current }
        .onChange(of: selectedRevision) {
            if selectedRevision != control.current, control.available.contains(selectedRevision) { setRevision(selectedRevision) }
        }
    }

    private var revisionHelp: String {
        let explanation: String
        if control.available.count >= 2 {
            explanation = "Show this file before or after the pull request (⌥⌘B)"
        } else {
            explanation = switch control.current {
            case .after: control.status == "Unchanged" ? "This file is identical before and after the pull request." : "This file was added by the pull request; it has no Before."
            case .before: "This file was deleted by the pull request; it has no After."
            }
        }
        return "\(control.status). \(explanation)"
    }
}
