import Foundation
import Testing
@testable import Radiology

@Suite(.serialized)
@MainActor
struct ReaderSessionTests {
    private static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition(), "timed out")
    }

    private static func model(_ fixture: GitFixture, preferences: UserDefaults, client: FakeGitHubClient) -> AppModel {
        let cache = IndexCache(root: fixture.directory.appending(path: "session-index-cache"))
        let semantics = SemanticModel(service: SemanticIndexService(indexers: [], cache: cache,
                                                                    tools: ToolDirectory(url: fixture.directory.appending(path: "tools"))))
        return AppModel(preferences: preferences, semantics: semantics,
                        pullRequests: PullRequestModel(client: client, workingTreeCache: cache))
    }

    @Test func relaunchRestoresTheAttachedRepositoryAndConfirmedPR() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let domain = "RadiologyTests.Session." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let client = FakeGitHubClient(summaries: [758: fixture.summary(number: 758)], mergeBase: fixture.baseSHA)
        let first = Self.model(fixture, preferences: preferences, client: client)
        await first.openRepository(fixture.attached, selecting: nil, pullRequest: 758)
        try await Self.waitUntil { first.review?.number == 758 && !first.isOpening && first.repository != nil }
        let remembered = ReaderSession(repositoryPath: fixture.attached.path, pullRequest: 758)
        #expect(first.sessionStore.load() == remembered)
        #expect(first.repository?.root != remembered.repositoryURL, "save the attached checkout, not an evictable PR worktree")

        // Another model and another preferences handle represent a new app launch.
        let freshPreferences = try #require(UserDefaults(suiteName: domain))
        let nextClient = FakeGitHubClient(summaries: [758: fixture.summary(number: 758)], mergeBase: fixture.baseSHA)
        nextClient.pullRequestDelay = .milliseconds(150)
        let relaunched = Self.model(fixture, preferences: freshPreferences, client: nextClient)
        await relaunched.launch(using: LaunchArguments(["Radiology"]))
        #expect(relaunched.sessionStore.load() == remembered, "preparing the local checkout must not erase the saved PR")
        try await Self.waitUntil { relaunched.review?.number == 758 && !relaunched.isOpening && relaunched.repository != nil }
        #expect(relaunched.attachedRoot == fixture.attached)
        #expect(relaunched.repository?.root == relaunched.review?.headRoot && relaunched.mode == .changes)
        #expect(nextClient.viewCalls == 1, "resolve fresh PR metadata on relaunch")
    }

    @Test func exitPRRemembersLocalCheckoutOnTheNextLaunch() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let domain = "RadiologyTests.Session." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let client = FakeGitHubClient(summaries: [1: fixture.summary()], mergeBase: fixture.baseSHA)
        let first = Self.model(fixture, preferences: preferences, client: client)
        await first.openRepository(fixture.attached, selecting: nil, pullRequest: 1)
        try await Self.waitUntil { first.review != nil && !first.isOpening && first.repository != nil }
        first.exitPullRequest()
        try await Self.waitUntil { !first.isOpening && first.repository != nil }
        #expect(first.sessionStore.load() == ReaderSession(repositoryPath: fixture.attached.path, pullRequest: nil))
        let views = client.viewCalls
        let relaunched = Self.model(fixture, preferences: preferences, client: client)
        await relaunched.launch(using: LaunchArguments(["Radiology"]))
        #expect(relaunched.repository?.root == fixture.attached && relaunched.review == nil)
        #expect(client.viewCalls == views)
    }

    @Test func explicitLaunchArgumentsOverrideTheSavedSession() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let domain = "RadiologyTests.Session." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let client = FakeGitHubClient(summaries: [2: fixture.summary(number: 2)], mergeBase: fixture.baseSHA)
        let model = Self.model(fixture, preferences: preferences, client: client)
        model.sessionStore.save(ReaderSession(repositoryPath: fixture.directory.appending(path: "missing").path, pullRequest: 758))
        await model.launch(using: LaunchArguments(["Radiology", "--repository", fixture.attached.path,
                                                  "--pull-request", "2", "--file", "src/lib.rs"]))
        try await Self.waitUntil { model.source?.path == "src/lib.rs" && !model.isLoadingSource }
        #expect(model.review?.number == 2 && model.source?.revision == .after)
        #expect(model.sessionStore.load() == ReaderSession(repositoryPath: fixture.attached.path, pullRequest: 2))

        let local = Self.model(fixture, preferences: preferences, client: client)
        let views = client.viewCalls
        await local.launch(using: LaunchArguments(["Radiology", "--repository", fixture.origin.path, "--file", "src/lib.rs"]))
        try await Self.waitUntil { local.source?.path == "src/lib.rs" && !local.isLoadingSource }
        #expect(local.repository?.root == fixture.origin && local.review == nil && client.viewCalls == views)
        #expect(local.sessionStore.load() == ReaderSession(repositoryPath: fixture.origin.path, pullRequest: nil))
    }

    @Test func failedRestoreKeepsThePRForRetry() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let domain = "RadiologyTests.Session." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let client = FakeGitHubClient(summaries: [758: fixture.summary(number: 758)], mergeBase: fixture.baseSHA)
        client.pullRequestError = "GitHub is offline"
        let model = Self.model(fixture, preferences: preferences, client: client)
        let remembered = ReaderSession(repositoryPath: fixture.attached.path, pullRequest: 758)
        model.sessionStore.save(remembered)
        await model.launch(using: LaunchArguments(["Radiology"]))
        try await Self.waitUntil { model.pullRequests.loadError != nil && !model.pullRequests.isLoading }
        #expect(model.sessionStore.load() == remembered && model.review == nil)
        #expect(model.pullRequests.failedNumber == 758 && model.repository?.root == fixture.attached)
        model.showPullRequestNumber()
        #expect(model.pullRequestNumberInput == 758)
        client.pullRequestError = nil
        model.openPullRequestFromSheet()
        try await Self.waitUntil { model.review?.number == 758 && !model.isOpening && model.repository != nil }
        #expect(model.sessionStore.load() == remembered)
    }

    @Test func failedAndCancelledPRChoicesDoNotReplaceTheConfirmedSession() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let domain = "RadiologyTests.Session." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let client = FakeGitHubClient(summaries: [1: fixture.summary()], mergeBase: fixture.baseSHA)
        client.summaries[2] = fixture.summary(number: 2)
        let model = Self.model(fixture, preferences: preferences, client: client)
        await model.openRepository(fixture.attached, selecting: nil, pullRequest: 1)
        try await Self.waitUntil { model.review?.number == 1 && !model.isOpening && model.repository != nil }
        let remembered = model.sessionStore.load()
        model.openPullRequest(999)
        try await Self.waitUntil { model.pullRequests.loadError != nil && !model.pullRequests.isLoading }
        #expect(model.review?.number == 1 && model.sessionStore.load() == remembered)
        client.pullRequestDelay = .seconds(2)
        model.openPullRequest(2)
        model.pullRequests.cancelOpen()
        #expect(model.review?.number == 1 && model.sessionStore.load() == remembered)
    }

    @Test func newerRepositoryChoiceWinsAndLaunchOnlyRunsOnce() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let domain = "RadiologyTests.Session." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let client = FakeGitHubClient(summaries: [758: fixture.summary(number: 758)], mergeBase: fixture.baseSHA)
        let model = Self.model(fixture, preferences: preferences, client: client)
        model.sessionStore.save(ReaderSession(repositoryPath: fixture.attached.path, pullRequest: 758))
        let launch = Task { await model.launch(using: LaunchArguments(["Radiology"])) }
        while !model.didStartLaunch { await Task.yield() }
        await model.openRepository(fixture.origin, selecting: nil)
        await launch.value
        #expect(model.repository?.root == fixture.origin && model.review == nil)
        #expect(client.viewCalls == 0, "a late startup preparation must not open the remembered PR in the newly chosen repository")
        await model.launch(using: LaunchArguments(["Radiology", "--repository", fixture.attached.path, "--pull-request", "758"]))
        #expect(model.repository?.root == fixture.origin && client.viewCalls == 0)
        #expect(model.sessionStore.load() == ReaderSession(repositoryPath: fixture.origin.path, pullRequest: nil))
    }

    @Test func missingRepositoryAndInvalidPreferencesHaveSafeRecovery() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let domain = "RadiologyTests.Session." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let client = FakeGitHubClient(summaries: [:], mergeBase: fixture.baseSHA)
        let model = Self.model(fixture, preferences: preferences, client: client)
        let remembered = ReaderSession(repositoryPath: fixture.directory.appending(path: "missing").path, pullRequest: 758)
        model.sessionStore.save(remembered)
        await model.launch(using: LaunchArguments(["Radiology"]))
        #expect(model.repository == nil && model.repositoryError != nil && model.sessionStore.load() == remembered)
        await model.openRepository(fixture.attached, selecting: nil)
        #expect(model.repository?.root == fixture.attached && model.repositoryError == nil)

        for payload in ["broken", "{\"repositoryPath\":\"relative\",\"pullRequest\":758}",
                        "{\"repositoryPath\":\"/tmp\",\"pullRequest\":0}"] {
            preferences.set(Data(payload.utf8), forKey: ReaderSessionStore.key)
            let empty = Self.model(fixture, preferences: preferences, client: client)
            await empty.launch(using: LaunchArguments(["Radiology"]))
            #expect(empty.repository == nil && empty.repositoryError == nil && empty.sessionStore.load() == nil)
        }
    }
}
