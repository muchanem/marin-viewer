import Foundation

extension AppModel {
    var canImportCodePath: Bool {
        repository != nil && codePaths.repositoryPath != nil && !isOpening && !pullRequests.isLoading
    }

    func showCodePathImport() {
        guard canImportCodePath else { return }
        sheet = .codePath
    }

    func importCodePath(_ text: String) throws {
        guard canImportCodePath else { throw BrowserError.message("Wait for the repository to finish opening.") }
        try codePaths.importText(text)
        showCodePaths()
        sheet = nil
    }

    func showCodePaths() {
        guard repository != nil else { return }
        mode = .codePaths
        sidebarRevealRevision += 1
    }

    func goToCodePathStep(_ id: UUID, variant: Int = 0) {
        guard canImportCodePath, let repository, let scope = codePaths.repositoryPath,
              let path = codePaths.selectedPath, let step = path.steps.first(where: { $0.id == id }) else { return }
        codePathNavigationTask?.cancel()
        codePaths.navigationError = nil
        codePaths.destinations = []
        codePaths.resolvedStepID = nil
        let navigation = navigationRevision
        let caret = sourceCaretRevision
        let origin = currentCaretLocation
        let openBuffer = source
        let revision: ReviewRevision? = isReviewing ? .after : nil
        codePathNavigationTask = Task { [codePathResolver] in
            do {
                let destinations = try await codePathResolver.resolve(step, root: repository.root, revision: revision, openBuffer: openBuffer)
                guard !Task.isCancelled, scope == codePaths.repositoryPath, repository.root == self.repository?.root,
                      navigation == navigationRevision, caret == sourceCaretRevision,
                      codePaths.selectedPath?.id == path.id else { return }
                guard destinations.indices.contains(variant) else { return }
                let destination = destinations[variant].location
                if let origin { navigateSemantically(from: origin, to: destination) }
                else { navigate(to: destination) }
                codePaths.selectedStepID = id
                codePaths.resolvedStepID = id
                codePaths.destinations = destinations
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, scope == codePaths.repositoryPath, repository.root == self.repository?.root,
                      navigation == navigationRevision, caret == sourceCaretRevision,
                      codePaths.selectedPath?.id == path.id else { return }
                codePaths.navigationError = error.localizedDescription
            }
        }
    }
}
