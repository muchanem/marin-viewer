import SwiftUI

/// A native dropdown whose title is the current mode; new sessions start Normal.
struct SourceModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker("Source Mode", selection: $model.sourceMode) {
            ForEach(SourceMode.allCases) { mode in Text(mode.title).tag(mode) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .disabled(model.source == nil)
        .help("Normal shows the source as written. Critical recedes runtime plumbing (⌥⌘1 / ⌥⌘2).")
    }
}
