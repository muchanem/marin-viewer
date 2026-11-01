import SwiftUI
import ViewerCore

/// The main view of an open PR until the diff reader (workstream 1, `DiffReaderView`) merges.
/// It shows what the reader will show from the same store state: By step, the current step's
/// excerpts; By file, every changed file; plus the reveal target, the focused note and blame.
/// See plans/shell.md for the seam the reader replaces this through.
struct ViewerMainPlaceholder: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.mode == .byStep, let step = store.focusedStep {
                        stepView(step)
                    } else {
                        filesView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: store.revealRequest?.revision) {
                guard let reveal = store.revealRequest else { return }
                withAnimation { proxy.scrollTo(reveal.inStep ? "excerpt:\(reveal.path)" : "file:\(reveal.path)", anchor: .top) }
            }
        }
        .background(Color.viewerBackground)
    }

    private func stepView(_ step: PRStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("STEP \(step.id) OF \(store.stepOrder.count)").font(ViewerFonts.cardTitle).tracking(0.6).foregroundStyle(.secondary)
                Text(step.title).font(.title3.weight(.semibold))
                Text(viewerInline(step.l1)).font(ViewerFonts.body).foregroundStyle(.secondary)
                if let l2 = step.l2, !l2.isEmpty {
                    Text(viewerInline(l2)).font(ViewerFonts.summary).padding(.top, 4)
                }
            }
            seamNote
            ForEach(Array(step.excerpts.enumerated()), id: \.offset) { _, excerpt in
                excerptCard(excerpt).id("excerpt:\(excerpt.path)")
            }
            if let next = store.step(after: step.id) {
                Button("Next: step \(next.id) · \(next.title)") { store.focus(step: next.id) }.buttonStyle(.link)
            }
        }
    }

    private func excerptCard(_ excerpt: Excerpt) -> some View {
        let reveal = store.revealRequest
        let highlighted = reveal?.inStep == true && reveal?.path == excerpt.path
        return fileCard(path: excerpt.path) {
            VStack(alignment: .leading, spacing: 3) {
                if !excerpt.functions.isEmpty {
                    Text(excerpt.functions.joined(separator: ", ")).font(ViewerFonts.mono)
                }
                if let range = excerpt.lineRange {
                    Text("lines \(range.lowerBound)–\(range.upperBound) at \(store.pr?.head.prefix(7) ?? "")")
                        .font(ViewerFonts.meta).foregroundStyle(.secondary)
                }
                if highlighted, let reveal {
                    revealLine(reveal)
                }
                notesInline(path: excerpt.path)
            }
        }
    }

    private var filesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ALL CHANGED FILES").font(ViewerFonts.cardTitle).tracking(0.6).foregroundStyle(.secondary)
            seamNote
            ForEach(store.pr?.changes ?? [], id: \.path) { change in
                fileCard(path: change.path) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let layers = store.pr?.wordbase.files[change.path] {
                            Text(viewerInline(layers.l1)).font(ViewerFonts.summary).foregroundStyle(.secondary)
                        }
                        if store.wholeFilePaths.contains(change.path) {
                            Text("Shown whole").font(ViewerFonts.meta).foregroundStyle(.secondary)
                        }
                        if let reveal = store.revealRequest, !reveal.inStep, reveal.path == change.path {
                            revealLine(reveal)
                        }
                        notesInline(path: change.path)
                    }
                }
                .id("file:\(change.path)")
            }
        }
    }

    private var seamNote: some View {
        Text("The diff reader draws this view. Until it merges, this lists what it will show\(store.blame ? ", with blame on" : "").")
            .font(ViewerFonts.meta).foregroundStyle(.secondary)
    }

    private func revealLine(_ reveal: RevealRequest) -> some View {
        Text("→ \(store.shortener.short(reveal.path))\(reveal.line.map { ":\($0)" } ?? "")\(reveal.function.map { " · \($0)" } ?? "")")
            .font(ViewerFonts.mono).foregroundStyle(Color.viewerNote)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.viewerNoteSoft, in: .rect(cornerRadius: 4))
            .accessibilityLabel("Revealed \(reveal.path) line \(reveal.line ?? 0)")
    }

    @ViewBuilder private func notesInline(path: String) -> some View {
        if let note = store.focusedNote, note.path == path {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(note.status.rawValue) · line \(note.line)").font(ViewerFonts.pill).foregroundStyle(Color.viewerNote)
                Text(viewerInline(note.l1)).font(ViewerFonts.summary)
            }
            .padding(8)
            .background(Color.viewerNoteSoft, in: .rect(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.viewerNote.opacity(0.3)) }
        }
    }

    private func fileCard(path: String, @ViewBuilder content: () -> some View) -> some View {
        let change = store.pr?.change(path: path)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(store.shortener.short(path)).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                if let additions = change?.additions, let deletions = change?.deletions {
                    Text("+\(additions)").foregroundStyle(Color.viewerOK) + Text(" −\(deletions)").foregroundStyle(Color.viewerBad)
                }
            }
            .font(ViewerFonts.meta.monospacedDigit())
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color(red: 0xfa / 255, green: 0xfb / 255, blue: 0xfc / 255))
            .contentShape(.rect)
            .onTapGesture {
                window.lastAskTarget = ChipFactory.file(path, commit: store.pr?.head ?? "", shortener: store.shortener)
            }
            .contextMenu { ViewerFileMenu(path: path) }
            .help(path)
            Divider()
            content().padding(10)
        }
        .background(.background, in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.viewerRule) }
    }
}
