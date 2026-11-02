import Foundation
import ViewerCore

/// A memory the closing turn proposed: `notes.proposed` and `notes.keep` carry these.
struct ProposedMemory: Codable, Hashable, Sendable, Identifiable {
    var target: String
    var text: String
    var commit: String
    var id: String { "\(target)\u{1F}\(text)" }
}

/// Everything the sidecar sends that is not an answer to one of our requests.
enum SidecarEvent: Sendable, Equatable {
    case delta(session: String, text: String)
    case turnResult(session: String, costUSD: Double, isError: Bool, text: String?)
    case uiCommand(session: String, name: String, args: [String: JSONValue])
    case notesProposed(session: String, notes: [ProposedMemory])
    case error(session: String?, message: String)
    /// The child process went away; every pending request has failed.
    case exited(String)
}

/// Whichever of an answer and its deadline finishes first wins.
@MainActor private final class BudgetRace {
    private var done = false
    func finish() -> Bool {
        defer { done = true }
        return !done
    }
}

/// `app.request {id, name, args}`: the sidecar asks the app (`find_symbol`, `selection_context`).
struct SidecarAppRequest: Sendable, Equatable {
    let id: JSONValue
    let name: String
    let args: [String: JSONValue]
}

@MainActor
protocol SidecarClientDelegate: AnyObject {
    func sidecarClient(_ client: SidecarClient, received event: SidecarEvent)
    /// Answers an `app.request`. The client sends whatever comes back as `app.response`, or an
    /// error when the answer takes longer than `SidecarClient.appRequestBudget`.
    func sidecarClient(_ client: SidecarClient, answer request: SidecarAppRequest) async throws -> JSONValue
}

/// The app side of the JSON-lines protocol in `sidecar/src/protocol.ts`: starts the transport on
/// first use, correlates `response`/`error` with request ids, dispatches events, and answers
/// `app.request` within the sidecar's 5 s window.
@MainActor
final class SidecarClient {
    /// The sidecar gives up on an `app.request` after 5 s; answer with room to spare.
    static let appRequestBudget: Duration = .milliseconds(4500)

    weak var delegate: (any SidecarClientDelegate)?
    private let makeTransport: () throws -> any SidecarTransport
    private var transport: (any SidecarTransport)?
    private var pending: [String: CheckedContinuation<JSONValue, any Error>] = [:]
    private var nextID = 1
    private(set) var exitReason: String?
    /// Every line sent and received, newest last, for tests and the panel's diagnostics.
    private(set) var transcript: [String] = []

    init(makeTransport: @escaping () throws -> any SidecarTransport) {
        self.makeTransport = makeTransport
    }

    var isRunning: Bool { transport != nil && exitReason == nil }

    /// Starts the child process if it is not running. A sidecar that exited is restarted.
    func start() throws {
        if transport != nil, exitReason == nil { return }
        let transport = try makeTransport()
        exitReason = nil
        try transport.start(onLine: { [weak self] line in
            Task { @MainActor in self?.receive(line) }
        }, onExit: { [weak self] reason in
            Task { @MainActor in self?.transportExited(reason) }
        })
        self.transport = transport
    }

    func stop() {
        transport?.stop()
        transport = nil
        failAll(SidecarError.notRunning)
    }

    /// Sends a message with a fresh `id` and waits for its `response` (or `error`).
    func request(_ message: [String: JSONValue]) async throws -> JSONValue {
        try start()
        let id = "app-\(nextID)"
        nextID += 1
        var message = message
        message["id"] = .string(id)
        let line = try JSONValue.object(message).line()
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try write(line)
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    /// Sends a message that needs no answer.
    func post(_ message: [String: JSONValue]) throws {
        try start()
        try write(try JSONValue.object(message).line())
    }

    private func write(_ line: Data) throws {
        guard let transport else { throw SidecarError.notRunning }
        record("→ " + String(decoding: line, as: UTF8.self))
        try transport.send(line)
    }

    // MARK: - Inbound

    func receive(_ line: Data) {
        record("← " + String(decoding: line, as: UTF8.self))
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: line), let type = message["type"]?.string else {
            delegate?.sidecarClient(self, received: .error(session: nil, message: "The sidecar sent a line that is not a JSON message."))
            return
        }
        let session = message["session"]?.string
        switch type {
        case "response":
            guard let id = message["id"].map(Self.key) else { return }
            pending.removeValue(forKey: id)?.resume(returning: message["result"] ?? .null)
        case "error":
            let text = message["message"]?.string ?? "unknown sidecar error"
            if let id = message["id"].map(Self.key), let continuation = pending.removeValue(forKey: id) {
                continuation.resume(throwing: SidecarError.failed(text))
            } else {
                delegate?.sidecarClient(self, received: .error(session: session, message: text))
            }
        case "stream.delta":
            delegate?.sidecarClient(self, received: .delta(session: session ?? "", text: message["text"]?.string ?? ""))
        case "turn.result":
            delegate?.sidecarClient(self, received: .turnResult(
                session: session ?? "", costUSD: message["cost_usd"]?.double ?? 0,
                isError: message["is_error"]?.bool ?? false, text: message["text"]?.string))
        case "ui.command":
            delegate?.sidecarClient(self, received: .uiCommand(
                session: session ?? "", name: message["name"]?.string ?? "", args: message["args"]?.object ?? [:]))
        case "notes.proposed":
            let notes = (try? message["notes"]?.decode([ProposedMemory].self)) ?? []
            delegate?.sidecarClient(self, received: .notesProposed(session: session ?? "", notes: notes))
        case "app.request":
            let request = SidecarAppRequest(id: message["id"] ?? .null, name: message["name"]?.string ?? "",
                                            args: message["args"]?.object ?? [:])
            Task { await answer(request) }
        default:
            delegate?.sidecarClient(self, received: .error(session: session, message: "The sidecar sent an unknown message type \(type)."))
        }
    }

    private func answer(_ request: SidecarAppRequest) async {
        var reply: [String: JSONValue] = ["type": "app.response", "id": request.id]
        do {
            guard let delegate else { throw SidecarError.unavailable("no viewer window is open") }
            reply["result"] = try await Self.withBudget(Self.appRequestBudget) {
                try await delegate.sidecarClient(self, answer: request)
            }
        } catch {
            reply["error"] = .string(error.localizedDescription)
        }
        try? post(reply)
    }

    /// Runs `work`, failing with `timedOut` once `budget` passes.
    static func withBudget(_ budget: Duration, _ work: @escaping @MainActor () async throws -> JSONValue) async throws -> JSONValue {
        let race = BudgetRace()
        return try await withCheckedThrowingContinuation { continuation in
            let worker = Task { @MainActor in
                let result: Result<JSONValue, any Error>
                do { result = .success(try await work()) } catch { result = .failure(error) }
                if race.finish() { continuation.resume(with: result) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: budget)
                guard race.finish() else { return }
                worker.cancel()
                continuation.resume(throwing: SidecarError.timedOut("the app request"))
            }
        }
    }

    private func transportExited(_ reason: String) {
        exitReason = reason
        transport = nil
        failAll(SidecarError.unavailable(reason))
        delegate?.sidecarClient(self, received: .exited(reason))
    }

    private func failAll(_ error: any Error) {
        let waiting = pending
        pending = [:]
        for continuation in waiting.values { continuation.resume(throwing: error) }
    }

    private func record(_ line: String) {
        transcript.append(line)
        if transcript.count > 400 { transcript.removeFirst(transcript.count - 400) }
    }

    private static func key(_ id: JSONValue) -> String {
        switch id {
        case .string(let value): value
        case .number(let value): String(Int(value))
        default: "\(id)"
        }
    }
}
