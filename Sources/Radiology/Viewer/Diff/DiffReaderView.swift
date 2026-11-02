import SwiftUI
import ViewerCore

/// The diff reader: a step header (By step) or a files header (By file),
/// then one card per excerpt or changed file with a sticky header, and a
/// "Next" link after the last excerpt of a step.
///
/// The cards live in a `LazyVStack` with sticky section headers; each body
/// is one AppKit view (`DiffCardBody`) holding a TextKit text view, so a
/// selection runs across a card's rows and only the visible part of a long
/// card is drawn.
struct DiffReaderView: View {
    @Bindable var model: DiffReaderModel
    private static let topID = "diff-reader-top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Group {
                        if model.mode == .byStep, let step = model.step {
                            DiffStepHeader(model: model, step: step)
                        } else {
                            DiffAllFilesHeader()
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                    .id(Self.topID)

                    ForEach(model.cards) { card in
                        if let file = model.document.file(card.path) {
                            Section {
                                cardBody(card, file: file)
                            } header: {
                                DiffFileHeader(model: model, card: card, file: file)
                                    .id(card.id)
                            }
                        }
                    }

                    if model.mode == .byStep, let next = model.nextStep {
                        Button("Next: \(next.step.title)") { model.focus(step: next.id) }
                            .buttonStyle(.bordered)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, DiffReaderStyle.readerHorizontalInset)
                .padding(.top, DiffReaderStyle.readerTopInset)
                .padding(.bottom, DiffReaderStyle.readerBottomInset)
            }
            .background(Color(nsColor: DiffReaderStyle.background))
            .onChange(of: model.scrollTarget) { _, target in follow(target, proxy: proxy) }
            // A reveal requested before the reader appeared.
            .onAppear { follow(model.scrollTarget, proxy: proxy) }
        }
    }

    /// Brings the target's card to the top; the card body then centres the
    /// row itself, because only it knows where the row is.
    private func follow(_ target: DiffReaderModel.ScrollTarget?, proxy: ScrollViewProxy) {
        guard let target else { return }
        if target.cardID.isEmpty {
            proxy.scrollTo(Self.topID, anchor: .top)
            model.scrollTargetHandled(target)
        } else if target.row != nil, model.mountedBodies.contains(target.cardID) {
            // The card's body centres the row; scrolling to the card as well would land after
            // it and leave the card's top in view instead.
        } else {
            proxy.scrollTo(target.cardID, anchor: .top)
            if target.row == nil { model.scrollTargetHandled(target) }
        }
    }

    @ViewBuilder
    private func cardBody(_ card: DiffReaderModel.Card, file: PRFileReview) -> some View {
        Group {
            if model.isCollapsed(card.path) {
                Color.clear.frame(height: 0)
            } else if file.diff.rows.isEmpty {
                Text(file.diff.isBinary ? "Binary file" : "No text changes")
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: DiffReaderStyle.muted))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: DiffReaderStyle.pane))
                    .modifier(DiffCardBottom())
            } else {
                DiffCardBody(model: model, content: DiffBodyContent(model: model, card: card, file: file),
                             scrollTarget: model.scrollTarget)
                    .modifier(DiffCardBottom())
            }
        }
        .padding(.bottom, DiffReaderStyle.cardSpacing)
    }
}

/// The lower half of a card's outline, joined under its header.
private struct DiffCardBottom: ViewModifier {
    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: DiffReaderStyle.cardCornerRadius,
                                           bottomTrailingRadius: DiffReaderStyle.cardCornerRadius)
        content
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color(nsColor: DiffReaderStyle.rule)) }
            .padding(.top, -1)
    }
}

/// By step / By file and Blame, for a toolbar the shell provides.
struct DiffReaderControls: View {
    @Bindable var model: DiffReaderModel

    var body: some View {
        Picker("Main view", selection: $model.mode) {
            ForEach(DiffReaderModel.Mode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        Toggle("Blame", isOn: $model.showBlame)
            .toggleStyle(.button)
    }
}
