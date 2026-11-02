import SwiftUI
import ViewerCore

/// The main window's toolbar while a PR is open: the sidebar toggle, the PR as the window's
/// title and subtitle (`ViewerPRTitle`), the By step / By file switch, Blame, and the panel
/// toggle. The title is the system's, so it truncates as the window narrows while the controls
/// keep their place. The earlier custom crumb item was the first thing the toolbar moved into
/// its overflow menu, and it took the controls with it.
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
        ToolbarItemGroup(placement: .primaryAction) {
            // By step / By file and Blame sit together, as in DESIGN.md §2 and the demo.
            @Bindable var store = store
            Picker("Main View", selection: $store.mode) {
                ForEach(ViewerMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Read one step's code, or every changed file (⌥⌘3, ⌥⌘4)")
            Toggle(isOn: $store.blame) {
                Label("Blame", systemImage: "person.text.rectangle")
            }
            .toggleStyle(.button)
            .labelStyle(.titleAndIcon)
            .help(store.blame ? "Hide who last changed each line" : "Show who last changed each line")
        }
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(isPanelPresented ? "Hide Session Panel" : "Show Session Panel", systemImage: "sidebar.right") {
                isPanelPresented.toggle()
            }
            .help("Show or Hide the Session Panel (⌥⌘I)")
        }
    }
}

/// The open PR as the window's title, "#10640 Add persistent container tasks…", and subtitle,
/// "marin · Merged · rjpower · 30 files · +4882 −388 · base 8a92f90 · head 01a8bb8". The demo
/// draws these as a crumb with a state pill; the system title truncates gracefully instead, so
/// the state moves into the subtitle.
struct ViewerPRTitle: ViewModifier {
    let pr: ViewerPR

    func body(content: Content) -> some View {
        content
            .navigationTitle(Text(verbatim: "#\(pr.number) \(pr.title)"))
            .navigationSubtitle(Text(verbatim: pr.subtitle))
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
            Text(verbatim: "PRs the poller prepared in \(store.paths.prsDirectory.path).").font(ViewerFonts.meta).foregroundStyle(.secondary)
            List(store.preparedPRs, id: \.self, selection: $selection) { number in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "#\(number)").font(ViewerFonts.body.weight(.medium))
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

/// In PR review the window shows the PR as its title (`ViewerPRTitle`). Otherwise the title is
/// the repository's, and Radiology hides it so that its repository menu names the window.
/// One title modifier only: SwiftUI keeps the innermost `navigationTitle`.
struct ViewerTitleOrReaderTitle: ViewModifier {
    let pr: ViewerPR?
    let readerTitle: String

    func body(content: Content) -> some View {
        if let pr {
            content.modifier(ViewerPRTitle(pr: pr))
        } else {
            content.navigationTitle(readerTitle).modifier(ReaderToolbarTitleVisibility())
        }
    }
}
