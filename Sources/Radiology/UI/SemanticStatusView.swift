import SwiftUI

/// The footer's unobtrusive index state. Clicking it opens the diagnostics
/// popover with the actual indexer, command, output, and actions.
struct SemanticStatusView: View {
    @Environment(AppModel.self) private var model
    @State private var showsDetails = false

    var body: some View {
        Button(action: { showsDetails.toggle() }) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel("Semantic index: \(title)")
        .accessibilityHint("Shows indexing details, diagnostics, and reindex controls.")
        .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
            SemanticStatusPopover()
        }
    }

    private var title: String {
        if model.source?.revision == .before { return "Not Indexed (Before)" }
        return switch model.semantics.status {
        case .noIndex: "No Index"
        case .indexing(let progress): progress.phase == .installing ? "Installing…" : "Indexing…"
        case .current: "Index Current"
        case .partial: "Index Partial"
        case .possiblyStale: "Index Stale"
        case .failed: "Index Failed"
        }
    }

    private var symbol: String {
        switch model.semantics.status {
        case .noIndex: "circle.dotted"
        case .indexing: "arrow.triangle.2.circlepath"
        case .current: "checkmark.circle"
        case .partial: "exclamationmark.circle"
        case .possiblyStale: "clock.badge.exclamationmark"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var help: String {
        if model.source?.revision == .before { return SemanticAvailability.revisionNotIndexed.explanation ?? "" }
        return switch model.semantics.status {
        case .noIndex(let reason): reason
        case .indexing(let progress): progress.message
        case .current: "Semantic navigation matches the current files."
        case .partial(let reason): reason
        case .possiblyStale(let reason): reason
        case .failed(let failure): failure.message
        }
    }
}

struct SemanticStatusPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            HStack {
                Text("Semantic Index").font(Theme.Fonts.heading)
                Spacer()
                Text(model.semantics.status.label).font(Theme.Fonts.meta).foregroundStyle(.secondary)
            }
            IndexingPersonalityPicker()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    statusDetail
                    if !model.semantics.outcomes.isEmpty {
                        Divider()
                        ForEach(model.semantics.outcomes) { outcome in
                            StrategyOutcomeRow(outcome: outcome)
                        }
                    }
                    if !model.semantics.skipped.isEmpty {
                        Text("\(model.semantics.skipped.count) more project directories were not indexed to bound work.")
                            .font(Theme.Fonts.meta).foregroundStyle(.secondary)
                    }
                    if !model.semantics.unsupportedLanguages.isEmpty {
                        Text("No indexer here for \(model.semantics.unsupportedLanguages.formatted(.list(type: .and))).")
                            .font(Theme.Fonts.meta).foregroundStyle(.secondary)
                        if needsClangBuildInstructions {
                            Text(ScipClangIndexer.buildRequirement)
                                .font(Theme.Fonts.meta).foregroundStyle(.secondary)
                        }
                    }
                    if let metadata = model.semantics.metadata {
                        Divider()
                        HStack(spacing: 4) {
                            Text("Generated \(metadata.generatedAt, format: .dateTime.day().month().hour().minute())")
                            if let commit = metadata.headCommit { Text("at \(commit.prefix(10))") }
                        }
                        .font(Theme.Fonts.meta).foregroundStyle(.secondary)
                    }
                    if let cache = model.semantics.cacheDirectory {
                        Button("Reveal Cache in Finder") { NSWorkspace.shared.activateFileViewerSelecting([cache]) }
                            .buttonStyle(.link).font(Theme.Fonts.meta)
                    }
                }
            }
            .frame(maxHeight: 520)
            Divider()
            HStack {
                if model.semantics.status.isIndexing {
                    Button("Cancel Indexing", action: model.cancelIndexing)
                } else {
                    Button("Reindex", action: model.reindexRepository).disabled(!model.semantics.isRepositoryOpen)
                }
                Spacer()
                if case .failed(let failure) = model.semantics.status, case .toolMissing(let canInstall) = failure.kind, canInstall {
                    Button("Install \(failure.indexerName)") { model.semantics.installIndexer(failure.indexerID) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(Theme.inset * 1.5)
        .frame(width: 440)
    }

    private var needsClangBuildInstructions: Bool {
        guard model.semantics.unsupportedLanguages.contains("C") || model.semantics.unsupportedLanguages.contains("C++") else { return false }
        if case .noIndex(let reason) = model.semantics.status, reason.contains(ScipClangIndexer.buildRequirement) { return false }
        return true
    }

    @ViewBuilder private var statusDetail: some View {
        switch model.semantics.status {
        case .noIndex(let reason):
            Text(reason).font(Theme.Fonts.meta).foregroundStyle(.secondary)
        case .indexing(let progress):
            HStack(spacing: Theme.spacing) {
                ProgressView().controlSize(.small)
                Text(progress.message).font(Theme.Fonts.meta).foregroundStyle(.secondary).lineLimit(2)
            }
            if progress.total > 1 { Text("Step \(progress.step) of \(progress.total)").font(Theme.Fonts.meta).foregroundStyle(.secondary) }
        case .current:
            Text("Definitions, references, and ⌘T symbols match the files on disk.").font(Theme.Fonts.meta).foregroundStyle(.secondary)
        case .partial(let reason):
            Text(reason).font(Theme.Fonts.meta).foregroundStyle(.secondary)
        case .possiblyStale(let reason):
            Text(reason + " Positions may be off until the index is regenerated.").font(Theme.Fonts.meta).foregroundStyle(.secondary)
        case .failed(let failure):
            IndexingFailureView(failure: failure)
        }
    }
}

struct StrategyOutcomeRow: View {
    let outcome: StrategyOutcome
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(outcome.strategy.indexerID).font(Theme.Fonts.body)
                if let version = outcome.indexerVersion { Text(version).font(Theme.Fonts.meta).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Text(resultLabel).font(Theme.Fonts.meta).foregroundStyle(.secondary)
            }
            Text(outcome.strategy.projectDirectory.isEmpty ? "Repository root · \(outcome.strategy.evidence.joined(separator: ", "))" : "\(outcome.strategy.projectDirectory) · \(outcome.strategy.evidence.joined(separator: ", "))")
                .font(Theme.Fonts.meta).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            if outcome.capability == .sourceOnlyNoDeps {
                Text("Partial: Cargo could not resolve this crate's dependencies\(outcome.cargoError.map { " (\($0))" } ?? ""). rust-analyzer indexed the crate's own sources with the sysroot only. Cross-crate types and dependency symbols are unresolved; intra-crate definitions, references, and ⌘T are real.")
                    .font(Theme.Fonts.meta).foregroundStyle(.secondary)
            } else if outcome.capability == .sysrootOnly {
                Text("Partial: only sysroot semantics are available for this project.")
                    .font(Theme.Fonts.meta).foregroundStyle(.secondary)
            } else if outcome.capability == .partialBuild {
                Text("Partial: some sources or build variants were not indexed. Compiler-resolved definitions and references in covered files remain available.")
                    .font(Theme.Fonts.meta).foregroundStyle(.secondary)
            } else if outcome.capability == .bestEffort {
                Text(ClangFallbackDatabase.explanation)
                    .font(Theme.Fonts.meta).foregroundStyle(.secondary)
            }
            if !outcome.missingFiles.isEmpty {
                DisclosureGroup("\(outcome.missingFiles.count) source files not covered") {
                    ForEach(outcome.missingFiles) { missing in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(missing.path).font(Theme.Fonts.identifier).textSelection(.enabled)
                            Text(missing.reason.rawValue).font(Theme.Fonts.meta).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(Theme.Fonts.meta)
            }
            if !outcome.diagnostics.isEmpty {
                DisclosureGroup("Indexer diagnostics") {
                    ScrollView {
                        Text(outcome.diagnostics).font(Theme.Fonts.identifier).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 120)
                }
                .font(Theme.Fonts.meta)
            }
            if case .failed(let failure) = outcome.result {
                DisclosureGroup("Failure details") { IndexingFailureView(failure: failure) }
                    .font(Theme.Fonts.meta)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var resultLabel: String {
        switch outcome.result {
        case .pending: return "Pending"
        case .cached(let stale):
            let label = outcome.capability == .bestEffort ? "Best effort, cached" : (outcome.capability == .fullWorkspace ? "Cached" : "Partial, cached")
            return (stale ? "\(label), stale" : label) + " · \(outcome.documentCount) files"
        case .generated:
            let prefix = outcome.capability == .bestEffort ? "Best effort" : (outcome.capability == .fullWorkspace ? "Generated" : "Partial")
            return outcome.strategy.sourceFileCount > 0
                ? "\(prefix) · \(outcome.documentCount) of \(outcome.strategy.sourceFileCount) files"
                : "\(prefix) · \(outcome.documentCount) files"
        case .reused(let from):
            let prefix = outcome.capability == .bestEffort ? "Best effort, reused" : (outcome.capability == .fullWorkspace ? "Reused" : "Partial, reused")
            return "\(prefix) from \(from) (identical bytes) · \(outcome.documentCount) files"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

/// Everything a reader needs to understand or report a failed run.
struct IndexingFailureView: View {
    let failure: IndexingFailure
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing / 2) {
            Text(failure.message).font(Theme.Fonts.body)
            if let version = failure.indexerVersion {
                Text("\(failure.indexerName) \(version)").font(Theme.Fonts.meta).foregroundStyle(.secondary)
            }
            if let commandLine = failure.commandLine {
                Text(commandLine).font(Theme.Fonts.identifier).foregroundStyle(.secondary).lineLimit(3).truncationMode(.middle).textSelection(.enabled)
            }
            if let status = failure.exitStatus {
                Text("Exit status \(status)" + (failure.signal.map { ", signal \($0)" } ?? "")).font(Theme.Fonts.meta).foregroundStyle(.secondary)
            }
            if !failure.stderr.isEmpty || !failure.stdout.isEmpty {
                ScrollView {
                    Text(failure.stderr.isEmpty ? failure.stdout : failure.stderr)
                        .font(Theme.Fonts.identifier)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(Theme.spacing)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
                .accessibilityLabel("Indexer output")
            }
        }
    }
}
