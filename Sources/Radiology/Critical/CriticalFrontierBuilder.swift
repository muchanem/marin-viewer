import Foundation

/// Bounded breadth-first expansion from one callable's direct calls. Pure
/// over a body provider so it can be tested on synthetic graphs.
///
/// Rules: a critical callee is emitted and never traversed; an ordinary
/// callee with a body is traversed transparently (it becomes a via step);
/// an ordinary callee without a body is a leaf with nothing to say; an
/// unknown callee is listed, never traversed, and makes coverage partial
/// (it may hide critical behavior). Call sites inside closures and nested
/// functions are conditional: never edges, and also partial, so a function
/// whose only calls are conditional is a lower bound, not a proven zero.
/// Cycles, self-recursion, and diamonds terminate through a visited set;
/// the first (shortest) path to a callee wins and later ones never inflate
/// the count. Depth and body limits mark the result truncated.
struct CriticalFrontierBuilder: Sendable {
    var maxDepth = 4
    var maxBodies = 48

    func build(root: CallableSummary, bodies: @Sendable (SemanticSymbolID) async -> CallableSummary?) async -> CriticalFrontier {
        var gaps = CallCoverageGaps()
        var rootNoBody: NoBodyReason?
        merge(root.coverage, into: &gaps, noBody: &rootNoBody)
        var visited = Set<SemanticSymbolID>()
        if let callable = root.callable { visited.insert(callable) }
        var criticalSeen = Set(root.criticalCalls.map(\.callee))
        var unknownSeen = Set<SemanticSymbolID>()
        var paths: [CriticalPath] = []
        var unknown: [CriticalPath] = []
        var queue: [(summary: CallableSummary, via: [ViaStep], depth: Int)] = [(root, [], 0)]
        var traversed = 0
        var head = 0
        while head < queue.count {
            let item = queue[head]
            head += 1
            gaps.conditionalSites += item.summary.conditionalSiteCount
            for call in item.summary.calls {
                switch call.classification.criticality {
                case .critical:
                    guard item.depth > 0, criticalSeen.insert(call.callee).inserted else { continue }
                    paths.append(CriticalPath(callee: call.callee, displayName: call.displayName, kind: call.kind,
                                              classification: call.classification, definition: call.definition,
                                              via: item.via, depth: item.depth + 1))
                case .unknown:
                    guard unknownSeen.insert(call.callee).inserted else { continue }
                    gaps.unknownCallees += 1
                    unknown.append(CriticalPath(callee: call.callee, displayName: call.displayName, kind: call.kind,
                                                classification: call.classification, definition: call.definition,
                                                via: item.via, depth: item.depth + 1))
                case .ordinary:
                    // Plumbing with no repository body is transparent and proves nothing missing.
                    guard call.hasBody, !call.isMacro else { continue }
                    guard visited.insert(call.callee).inserted else { continue }
                    if item.depth + 1 >= maxDepth || traversed >= maxBodies {
                        gaps.truncated = true
                        continue
                    }
                    traversed += 1
                    guard let body = await bodies(call.callee) else {
                        gaps.missingBodies += 1
                        continue
                    }
                    var bodyNoBody: NoBodyReason?
                    merge(body.coverage, into: &gaps, noBody: &bodyNoBody)
                    if bodyNoBody != nil { continue }
                    queue.append((body, item.via + [ViaStep(symbol: call.callee, displayName: call.displayName, definition: call.definition)],
                                  item.depth + 1))
                }
            }
        }
        let coverage: CallCoverage
        if let rootNoBody {
            coverage = .noBody(rootNoBody)
        } else {
            coverage = gaps.isEmpty ? .complete : .partial(gaps)
        }
        return CriticalFrontier(summary: root, paths: paths, unknown: unknown, coverage: coverage, traversedBodies: traversed)
    }

    private func merge(_ coverage: CallCoverage, into gaps: inout CallCoverageGaps, noBody: inout NoBodyReason?) {
        switch coverage {
        case .complete: break
        case .partial(let other): gaps.merge(other)
        case .noBody(let reason):
            noBody = reason
            gaps.missingBodies += 1
        }
    }
}
