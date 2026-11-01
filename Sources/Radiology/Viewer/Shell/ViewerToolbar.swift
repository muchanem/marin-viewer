import SwiftUI
import ViewerCore

/// The main window's toolbar while a PR is open: the PR crumb with its state pill and counts,
/// the By step / By file switch, Blame, and the panel toggle.
struct ViewerToolbar: ToolbarContent {
    @Environment(ViewerStore.self) private var store
    @Binding var sidebarVisibility: NavigationSplitViewVisibility
    @Binding var isPanelPresented: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(sidebarVisibility == .detailOnly ? "Show Navigation Sidebar" : "Hide Navigation Sidebar",
                   systemImage: "sidebar.left") {
                sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly
            }
            .help("Show or Hide the Navigation Sidebar (⌃⌘S)")
        }
        ToolbarItem(placement: .navigation) {
            PRCrumb()
        }
        ToolbarItem(placement: .principal) {
            @Bindable var store = store
            Picker("Main view", selection: $store.mode) {
                ForEach(ViewerMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Read one step's code, or every changed file")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            @Bindable var store = store
            Toggle("Blame", systemImage: "person.text.rectangle", isOn: $store.blame)
                .help("Show who last changed each line")
            Button(isPanelPresented ? "Hide Session Panel" : "Show Session Panel", systemImage: "sidebar.right") {
                isPanelPresented.toggle()
            }
            .help("Show or Hide the Session Panel (⌥⌘I)")
        }
    }
}

/// "marin / #10640 Add persistent container tasks…", the state pill, and the PR's counts.
struct PRCrumb: View {
    @Environment(ViewerStore.self) private var store

    var body: some View {
        if let pr = store.pr {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    (Text(pr.repoName).foregroundStyle(.secondary) + Text(" / ").foregroundStyle(.tertiary)
                        + Text("#\(pr.number) ") + Text(pr.title).foregroundStyle(.secondary))
                        .font(.headline)
                        .lineLimit(1).truncationMode(.tail)
                    ViewerPill(text: pr.stateTitle, fill: .viewerStateFill, ink: .viewerStateInk)
                }
                Text(pr.metaLine).font(ViewerFonts.meta).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 4)
            .help("\(pr.header.repo ?? "marin")#\(pr.number): \(pr.title)\n\(pr.metaLine)")
            .accessibilityElement(children: .combine)
        }
    }
}

/// File > Open PR…: the PRs prepared under `wordbase/prs/`.
struct OpenPRSheet: View {
    @Environment(ViewerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open a Prepared PR").font(.headline)
            Text("PRs the poller prepared in \(store.paths.prsDirectory.path).").font(ViewerFonts.meta).foregroundStyle(.secondary)
            List(store.preparedPRs, id: \.self, selection: $selection) { number in
                VStack(alignment: .leading, spacing: 1) {
                    Text("#\(number)").font(ViewerFonts.body.weight(.medium))
                    Text(Self.title(of: number, in: store.paths)).font(ViewerFonts.meta).foregroundStyle(.secondary).lineLimit(1)
                }
                .tag(number)
            }
            .frame(minHeight: 180)
            .overlay {
                if store.preparedPRs.isEmpty {
                    ContentUnavailableView("No Prepared PRs", systemImage: "tray",
                                           description: Text("The poller has not prepared any pull requests yet."))
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open") {
                    guard let selection else { return }
                    dismiss()
                    Task { await store.openPR(selection) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
        .onAppear {
            store.refreshPreparedPRs()
            selection = selection ?? store.preparedPRs.first
        }
    }

    /// The `title:` line of `pr.md`, without decoding the whole PR.
    static func title(of number: Int, in paths: ViewerPaths) -> String {
        guard let text = try? String(contentsOf: paths.prDirectory(number).appending(path: "pr.md"), encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("title:") }) else { return "" }
        return line.dropFirst("title:".count).trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
    }
}

/// A short message at the bottom of the main window.
struct ViewerToastView: View {
    let toast: ViewerToast

    var body: some View {
        Text(toast.text)
            .font(ViewerFonts.summary)
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.viewerInk, in: .rect(cornerRadius: 7))
            .frame(maxWidth: 560)
            .padding(.bottom, 18)
            .transition(.opacity)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
