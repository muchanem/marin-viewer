import SwiftUI

struct GoToLineSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Theme.inset) {
            Text("Go to Line").font(Theme.Fonts.heading)
            TextField("Line number", value: $model.lineInput, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).focused($focused).onSubmit(model.goToLine)
            Text("1–\(model.source?.lineCount ?? 1)").font(Theme.Fonts.meta).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Go", action: model.goToLine).keyboardShortcut(.defaultAction)
            }
        }.padding(Theme.inset * 2).frame(width: 300).task { focused = true }
    }
}
