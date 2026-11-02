import Foundation

extension AppModel {
    func openTraitImplementation(id: TraitImplementation.ID) {
        guard context.implementations.item(id: id) != nil else { return }
        context.implementations.selectedID = id
        commitImplementation(id: id)
    }

    func commitImplementation(id: TraitImplementation.ID) {
        let pane = context.implementations
        guard let item = pane.item(id: id), let root = repository?.root else { return }
        let origin = currentCaretLocation
        let generation = semanticNavigationGeneration
        let indexRevision = semantics.indexRevision
        pane.navigationError = nil
        Task { [worker = pane.worker] in
            do {
                let destination = try await worker.resolve(item, root: root)
                guard generation == semanticNavigationGeneration, repository?.root == root,
                      semantics.indexRevision == indexRevision, pane.item(id: id) == item else { return }
                navigateSemantically(from: origin ?? destination, to: destination)
            } catch {
                guard generation == semanticNavigationGeneration, repository?.root == root,
                      semantics.indexRevision == indexRevision, pane.item(id: id) == item else { return }
                pane.navigationError = error.localizedDescription
            }
        }
    }
}
