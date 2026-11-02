import Foundation

struct ReferenceCallTree: Sendable, Equatable {
    let callers: [ReferenceCaller]
    let notices: [String]
    let hasMore: Bool
    let budget: Int

    enum Phase: Sendable, Equatable {
        case loading
        case loaded(ReferenceCallTree)
        case failed(String)
    }
}
