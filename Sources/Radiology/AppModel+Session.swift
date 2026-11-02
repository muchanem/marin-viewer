import Foundation

extension AppModel {
    /// Called by the window task once. Explicit CLI intent wins; an ordinary
    /// launch restores the last successfully opened repository/PR.
    func launch(using arguments: LaunchArguments) async {
        guard !didStartLaunch, !Task.isCancelled else { return }
        didStartLaunch = true
        guard repository == nil, !isOpening else { return }
        if let root = arguments.repository {
            await openRepository(URL(filePath: root), selecting: arguments.file, pullRequest: arguments.pullRequest)
            return
        }
        guard let session = sessionStore.load() else { return }
        let root = session.repositoryURL
        restoringSessionRoot = root
        // Open the checkout as preparation, without persisting a transient
        // Local Checkout choice over the remembered PR.
        beginOpening(root: root, review: nil)
        let pending = currentRepositoryOpening()
        await pending.task?.value
        guard !Task.isCancelled, restoringSessionRoot == root,
              repositoryOpeningMatches(pending.generation) else { return }
        restoringSessionRoot = nil
        guard repository != nil else { return } // Existing repository error UI handles recovery.
        if let number = session.pullRequest {
            openPullRequest(number)
        } else if let attachedRoot {
            sessionStore.save(ReaderSession(repositoryPath: attachedRoot.path, pullRequest: nil))
        }
    }
}
