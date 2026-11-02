import Foundation
import Testing
import ViewerCore
@testable import Radiology

@MainActor
final class RecordingDelegate: SidecarClientDelegate {
    var events: [SidecarEvent] = []
    var answer: (SidecarAppRequest) async throws -> JSONValue = { _ in ["ok": true] }

    func sidecarClient(_ client: SidecarClient, received event: SidecarEvent) { events.append(event) }
    func sidecarClient(_ client: SidecarClient, answer request: SidecarAppRequest) async throws -> JSONValue {
        try await answer(request)
    }
}

@Suite(.serialized) @MainActor
struct SidecarClientTests {
    @Test func requestsCorrelateWithTheirResponses() async throws {
        let transport = ScriptedTransport { message in
            [ScriptedTransport.response(message, ["echo": message["type"] ?? .null])]
        }
        let client = SidecarClient(makeTransport: { transport })
        async let first = client.request(["type": "layout"])
        async let second = client.request(["type": "notes.keep"])
        let (a, b) = try await (first, second)
        #expect(a["echo"]?.string == "layout" && b["echo"]?.string == "notes.keep")
        #expect(Set(transport.sent.compactMap { $0["id"]?.string }).count == 2)
    }

    @Test func anErrorWithAnIDFailsThatRequest() async {
        let transport = ScriptedTransport { message in
            [["type": "error", "id": message["id"] ?? .null, "message": "bad diagram"]]
        }
        let client = SidecarClient(makeTransport: { transport })
        await #expect(throws: SidecarError.failed("bad diagram")) { _ = try await client.request(["type": "layout"]) }
    }

    @Test func eventsReachTheDelegate() async throws {
        let transport = ScriptedTransport()
        let client = SidecarClient(makeTransport: { transport })
        let delegate = RecordingDelegate()
        client.delegate = delegate
        try client.start()
        try transport.emit(["type": "stream.delta", "session": "s", "text": "Hel"])
        try transport.emit(["type": "turn.result", "session": "s", "cost_usd": 0.25, "usage": [:]])
        try transport.emit(["type": "ui.command", "session": "s", "name": "open_location", "args": ["path": "a.py", "line": 3]])
        try transport.emit(["type": "notes.proposed", "session": "s", "notes": [["target": "t", "text": "x", "commit": "c"]]])
        try transport.emit(["type": "error", "message": "oops"])
        #expect(await eventually { delegate.events.count == 5 })
        #expect(delegate.events[0] == .delta(session: "s", text: "Hel"))
        #expect(delegate.events[1] == .turnResult(session: "s", costUSD: 0.25, isError: false, text: nil))
        #expect(delegate.events[2] == .uiCommand(session: "s", name: "open_location", args: ["path": "a.py", "line": 3]))
        #expect(delegate.events[3] == .notesProposed(session: "s", notes: [ProposedMemory(target: "t", text: "x", commit: "c")]))
        #expect(delegate.events[4] == .error(session: nil, message: "oops"))
    }

    @Test func appRequestsAreAnsweredWithTheirID() async throws {
        let transport = ScriptedTransport()
        let client = SidecarClient(makeTransport: { transport })
        let delegate = RecordingDelegate()
        delegate.answer = { request in ["name": .string(request.name)] }
        client.delegate = delegate
        try client.start()
        try transport.emit(["type": "app.request", "id": "r1", "name": "selection_context", "args": [:]])
        #expect(await eventually { !transport.sent(type: "app.response").isEmpty })
        let reply = try #require(transport.sent(type: "app.response").first)
        #expect(reply["id"]?.string == "r1" && reply["result"]?["name"]?.string == "selection_context" && reply["error"] == nil)
    }

    @Test func aSlowAnswerBecomesAnErrorBeforeTheSidecarGivesUp() async throws {
        let started = ContinuousClock.now
        let result = try? await SidecarClient.withBudget(.milliseconds(50)) {
            try await Task.sleep(for: .seconds(5))
            return .null
        }
        #expect(result == nil && ContinuousClock.now - started < .seconds(2))
        #expect(SidecarClient.appRequestBudget < .seconds(5))
        let quick = try await SidecarClient.withBudget(.seconds(1)) { ["x": 1] }
        #expect(quick["x"]?.int == 1)
    }

    @Test func anExitFailsPendingRequestsAndRestartsOnTheNextOne() async throws {
        let transport = ScriptedTransport { _ in [] }
        var starts = 0
        let client = SidecarClient(makeTransport: { starts += 1; return transport })
        let delegate = RecordingDelegate()
        client.delegate = delegate
        let pending = Task { try await client.request(["type": "layout"]) }
        #expect(await eventually { !transport.sent.isEmpty })
        transport.exit("the sidecar exited with status 1")
        await #expect(throws: SidecarError.unavailable("the sidecar exited with status 1")) { _ = try await pending.value }
        #expect(delegate.events.contains(.exited("the sidecar exited with status 1")))
        #expect(!client.isRunning)
        try client.start()
        #expect(starts == 2 && client.isRunning)
    }
}
