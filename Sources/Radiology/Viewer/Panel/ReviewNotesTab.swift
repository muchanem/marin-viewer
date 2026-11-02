import SwiftUI
import ViewerCore

/// The Review notes tab: one card per note, with the post bar under them.
struct ReviewNotesTab: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window

    var body: some View {
        @Bindable var window = window
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(store.notes.notes) { note in
                            ReviewNoteCard(note: note, isFocused: store.focusedNoteID == note.id).id(note.id)
                        }
                        if store.notes.notes.isEmpty {
                            Text("No review notes yet. A session drafts them, and so does the preparation turn.")
                                .font(ViewerFonts.meta).foregroundStyle(.secondary)
                        }
                    }
                    .padding(Theme.inset)
                }
                .onChange(of: store.focusedNoteID, initial: true) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                if let error = store.notesError {
                    Text(error).font(ViewerFonts.meta).foregroundStyle(Color.viewerBad)
                }
                Button(store.notes.postButtonTitle) { window.isPostConfirmationPresented = true }
                    .disabled(store.notes.approved.isEmpty || store.isPosting)
                    .frame(maxWidth: .infinity)
                Text(store.notes.draftHint).font(ViewerFonts.meta).foregroundStyle(.secondary)
            }
            .padding(Theme.inset)
        }
        .sheet(isPresented: $window.isPostConfirmationPresented) {
            PostConfirmationSheet()
        }
    }
}

struct ReviewNoteCard: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window
    let note: ReviewNote
    let isFocused: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ViewerPill(text: note.status.rawValue, fill: Self.fill(note.status), ink: Self.ink(note.status))
                    .strikethrough(note.status == .rejected)
                ViewerPill(text: note.severity.rawValue, fill: .viewerSoft, ink: Color(red: 0x4a / 255, green: 0x53 / 255, blue: 0x61 / 255))
                Button(String("\(store.shortener.short(note.path)):\(note.line)")) { store.revealNote(note.id) }
                    .buttonStyle(.link).font(ViewerFonts.mono)
                    .help("Open \(note.path) at line \(note.line)")
                Text(note.who).font(ViewerFonts.meta).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(viewerInline(note.l1)).font(ViewerFonts.body).fixedSize(horizontal: false, vertical: true)
            if !note.l2.isEmpty {
                if expanded {
                    Text(viewerInline(note.l2)).font(ViewerFonts.summary).foregroundStyle(Color.viewerInk.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(expanded ? "Less" : "More") { expanded.toggle() }.buttonStyle(.link).font(ViewerFonts.meta)
            }
            if !note.status.actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(note.status.actions, id: \.self) { action in
                        Button(action.title) { store.apply(action, to: note.id) }.controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused ? Color.viewerNote : Color.viewerRule, lineWidth: isFocused ? 1.5 : 1)
        }
        .contentShape(.rect)
        .onTapGesture { window.lastAskTarget = ChipFactory.note(note, shortener: store.shortener) }
        .contextMenu {
            Button("Ask About This Note") { store.ask(ChipFactory.note(note, shortener: store.shortener), from: window) }
                .keyboardShortcut(">", modifiers: .command)
            Button("Show in Code") { store.revealNote(note.id) }
        }
    }

    static func fill(_ status: ReviewNote.Status) -> Color {
        switch status {
        case .draft: .viewerNoteSoft
        case .approved: Color(red: 0xe3 / 255, green: 0xf3 / 255, blue: 0xe6 / 255)
        case .posted: .viewerAccentSoft
        case .rejected, .resolved: .viewerSoft
        }
    }

    static func ink(_ status: ReviewNote.Status) -> Color {
        switch status {
        case .draft: .viewerNote
        case .approved: .viewerOK
        case .posted: .viewerAccent
        case .rejected, .resolved: .viewerMuted
        }
    }
}

/// The exact text that will post, and the one button that posts it.
struct PostConfirmationSheet: View {
    @Environment(ViewerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let repo = store.pr?.header.repo ?? "marin-community/marin"
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "Post \(store.notes.approved.count) Approved \(store.notes.approved.count == 1 ? "Note" : "Notes")").font(.headline)
            Text(verbatim: "These comments will post as one pending review on \(repo)#\(store.pr?.number ?? 0) from your account:")
                .font(ViewerFonts.summary)
            ScrollView {
                Text(store.notes.postConfirmationText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 160, maxHeight: 320)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.viewerRule) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Post Review") {
                    Task {
                        await store.postApprovedNotes()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(store.isPosting)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
