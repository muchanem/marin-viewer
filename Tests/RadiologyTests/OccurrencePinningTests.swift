import Foundation
import Testing
@testable import Radiology

@MainActor
struct OccurrencePinningTests {
    @Test func multiplePinsPersistAndUnpinIndependentlyWithoutRecoloring() {
        let source = SourceContentIdentity(Data("alpha beta alpha beta".utf8))
        let symbolA = SemanticSymbolID(symbol: "scip . alpha.", document: "file.rs")
        let symbolB = SemanticSymbolID(symbol: "scip . beta.", document: "file.rs")
        let a = OccurrenceGroup(identity: .semantic(symbolA), activeByteRange: 0..<5,
                                byteRanges: [0..<5, 11..<16])
        let b = OccurrenceGroup(identity: .semantic(symbolB), activeByteRange: 6..<10,
                                byteRanges: [6..<10, 17..<21])
        var pins = OccurrencePinStore()

        let pinnedA = pins.toggle(a, path: "file.rs", sourceIdentity: source, clickedByte: 1)
        let pinnedB = pins.toggle(b, path: "file.rs", sourceIdentity: source, clickedByte: 7)
        #expect(pinnedA)
        #expect(pinnedB)
        let both = pins.groups(path: "file.rs", sourceIdentity: source)
        #expect(both.map(\.colorSlot) == [0, 1])

        let removedA = pins.toggle(a, path: "file.rs", sourceIdentity: source, clickedByte: 12)
        #expect(!removedA)
        let remaining = pins.groups(path: "file.rs", sourceIdentity: source)
        #expect(remaining.count == 1)
        #expect(remaining.first?.identity == b.identity)
        #expect(remaining.first?.colorSlot == 1, "removing another group must not recolor an existing pin")
    }

    @Test func pinsArePerFileSurviveRevisitAndInvalidateOnChangedBytes() {
        let original = SourceContentIdentity(Data("let value = value".utf8))
        let changed = SourceContentIdentity(Data("let value = other".utf8))
        let group = OccurrenceGroup(identity: .syntactic(scope: 0..<17, spelling: Data("value".utf8)),
                                    activeByteRange: 4..<9, byteRanges: [4..<9, 12..<17])
        var pins = OccurrencePinStore()
        pins.toggle(group, path: "a.rs", sourceIdentity: original, clickedByte: 5)

        #expect(pins.groups(path: "b.rs", sourceIdentity: original).isEmpty)
        #expect(pins.groups(path: "a.rs", sourceIdentity: original).count == 1,
                "returning to an unchanged document must restore session pins")
        pins.reconcile(path: "a.rs", sourceIdentity: changed)
        #expect(pins.groups(path: "a.rs", sourceIdentity: changed).isEmpty,
                "changed bytes must not inherit stale canonical ranges")
    }

    @Test func semanticArrivalCanToggleTheEquivalentFallbackGroup() {
        let source = SourceContentIdentity(Data("fn f(x: i32) { let x = x; }".utf8))
        let ranges = [5..<6, 19..<20, 23..<24]
        let fallback = OccurrenceGroup(identity: .syntactic(scope: 0..<29, spelling: Data("x".utf8)),
                                       activeByteRange: ranges[0], byteRanges: ranges)
        let semantic = OccurrenceGroup(identity: .semantic(SemanticSymbolID(symbol: "local x", document: "a.rs")),
                                       activeByteRange: ranges[2], byteRanges: ranges)
        var pins = OccurrencePinStore()
        pins.toggle(fallback, path: "a.rs", sourceIdentity: source, clickedByte: 5)
        let removedFallback = pins.toggle(semantic, path: "a.rs", sourceIdentity: source, clickedByte: 23)
        #expect(!removedFallback)
        #expect(pins.groups(path: "a.rs", sourceIdentity: source).isEmpty)
    }

    @Test func androidMessagePinsFourTokensThenWhitespaceAndAnotherSelectionDoNotRemoveIt() async throws {
        let text = """
        #[cfg(target_os = "android")]
        fn android_log(message: &str) {
            let message = std::ffi::CString::new(message).unwrap();
            unsafe { __android_log_write(6, c"message", message.as_ptr()); }
        }
        fn other(message: &str) { println!("message {message}"); }
        """
        let buffer = try SourceBuffer(path: "app_image.rs", data: Data(text.utf8))
        let snapshot = try #require(try await SyntaxWorker().parse(buffer))
        let binding = try #require(buffer.data.range(of: Data("let message".utf8)))
        let messageByte = binding.lowerBound + 5
        let model = AppModel(preferences: UserDefaults(suiteName: UUID().uuidString)!)
        model.source = buffer
        model.syntax = snapshot
        model.sourceContentIdentity = SourceContentIdentity(buffer.data)

        model.selectOccurrences(at: messageByte)
        #expect(model.syntacticOccurrenceSelection?.byteRanges.count == 4)
        model.togglePinnedOccurrences(at: messageByte)
        #expect(model.pinnedOccurrenceGroups.count == 1)
        #expect(model.pinnedOccurrenceGroups.first?.byteRanges.count == 4)
        #expect(model.syntacticOccurrenceSelection == nil, "the first click of a double-click must not mask the pin")

        let otherByte = try #require(buffer.data.range(of: Data("__android_log_write".utf8))).lowerBound
        model.selectOccurrences(at: otherByte)
        #expect(model.pinnedOccurrenceGroups.count == 1, "a transient selection must preserve prior pins")
        model.togglePinnedOccurrences(at: otherByte)
        #expect(model.pinnedOccurrenceGroups.count == 2, "multiple groups may be pinned at once")

        model.selectOccurrences(at: nil)
        #expect(model.pinnedOccurrenceGroups.count == 2, "whitespace only clears transient highlighting")
        model.togglePinnedOccurrences(at: messageByte)
        #expect(model.pinnedOccurrenceGroups.count == 1, "unpinning one group must preserve every other pin")
        #expect(model.pinnedOccurrenceGroups.first?.byteRanges.contains(where: { $0.contains(otherByte) }) == true)
        #expect(model.syntacticOccurrenceSelection == nil, "unpin must leave no transient wash")
    }
}
