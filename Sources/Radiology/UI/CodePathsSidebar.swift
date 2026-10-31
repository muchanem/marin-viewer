import SwiftUI

struct CodePathsSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var paths = model.codePaths
        VStack(spacing: 0) {
            ContextRegionHeader(title: "Code Paths", detail: paths.selectedPath.map { "\($0.steps.count) \($0.steps.count == 1 ? "step" : "steps")" }) {
                Button("Import Code Path…", systemImage: "plus", action: model.showCodePathImport)
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .disabled(!model.canImportCodePath).help("Import Code Path (⇧⌘P)")
                Menu("Code Path Actions", systemImage: "ellipsis") {
                    Button("Copy Code Path", action: copyPath).disabled(paths.selectedPath == nil)
                    Button("Delete Code Path", role: .destructive, action: paths.removeSelectedPath)
                        .disabled(paths.selectedPath == nil)
                }
                .labelStyle(.iconOnly).menuStyle(.borderlessButton).fixedSize()
            }
            if let error = paths.storageError ?? paths.navigationError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(Theme.Fonts.meta).foregroundStyle(.secondary)
                    .lineLimit(5).help(error)
                    .textSelection(.enabled).padding(Theme.inset)
            }
            if paths.destinations.count > 1, let stepID = paths.resolvedStepID {
                Menu("\(paths.destinations.count) conditional definitions") {
                    ForEach(Array(paths.destinations.enumerated()), id: \.element.id) { index, destination in
                        Button("Definition \(index + 1) · line \(destination.line)") {
                            model.goToCodePathStep(stepID, variant: index)
                        }
                    }
                }
                .font(Theme.Fonts.meta).padding(.horizontal, Theme.inset)
                .help("The trace opens the first source definition. Choose another definition here; no build configuration is implied.")
            }
            if paths.paths.isEmpty {
                ContextStatusLine(text: paths.repositoryPath == nil ? "No Repository" : "No Code Paths",
                                  detail: "Import an agent’s trace with ⇧⌘P, then follow its steps through the source.",
                                  systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .padding(Theme.inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Picker("Code Path", selection: $paths.selectedPathID) {
                    ForEach(paths.paths) { path in
                        Text(path.title).tag(Optional(path.id))
                    }
                }
                .labelsHidden().pickerStyle(.menu)
                .padding(.horizontal, Theme.inset)
                .help(paths.selectedPath?.title ?? "Choose a code path")
                List(selection: $paths.selectedStepID) {
                    if let path = paths.selectedPath {
                        // EnumeratedSequence gains RandomAccessCollection only on macOS 26.
                        ForEach(Array(path.steps.enumerated()), id: \.element.id) { index, step in
                            Button { model.goToCodePathStep(step.id) } label: {
                                CodePathStepRow(step: step, number: index + 1)
                            }
                            .buttonStyle(.plain).tag(step.id)
                            .contextMenu {
                                Button("Open Source") { model.goToCodePathStep(step.id) }
                            }
                        }
                    }
                }
                .listStyle(.sidebar).scrollContentBackground(.hidden)
                .onKeyPress(.return, action: openSelection)
                .id(paths.selectedPathID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("code-paths-sidebar")
        .disabled(model.isOpening || model.pullRequests.isLoading)
    }

    private func copyPath() {
        guard let text = model.codePaths.selectedPath?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openSelection() -> KeyPress.Result {
        guard let id = model.codePaths.selectedStepID else { return .ignored }
        model.goToCodePathStep(id)
        return .handled
    }
}
