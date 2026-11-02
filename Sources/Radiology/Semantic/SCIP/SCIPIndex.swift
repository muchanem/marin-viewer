import Foundation

/// Decoded SCIP (`scip.proto`) data. These types mirror the wire schema and
/// stay inside the semantic layer; the UI only sees `SemanticIndex` values.
struct SCIPIndex: Sendable {
    var metadata = SCIPMetadata()
    var documents: [SCIPDocument] = []
    var externalSymbols: [SCIPSymbolInformation] = []
}

struct SCIPMetadata: Sendable, Equatable {
    var toolName = ""
    var toolVersion = ""
    var toolArguments: [String] = []
    var projectRoot = ""
    /// `TextEncoding` of the indexed files; 1 = UTF-8, 2 = UTF-16.
    var textDocumentEncoding = 0
}

struct SCIPDocument: Sendable {
    var relativePath = ""
    var language = ""
    var occurrences: [SCIPOccurrence] = []
    var symbols: [SCIPSymbolInformation] = []
    /// `PositionEncoding`: 0 unspecified, 1 UTF-8, 2 UTF-16, 3 UTF-32 code units.
    var positionEncoding = 0
}

/// Zero-based, half-open `[start, end)` coordinates in the document's encoding.
struct SCIPRange: Sendable, Hashable {
    var startLine: Int
    var startCharacter: Int
    var endLine: Int
    var endCharacter: Int

    /// Accepts the deprecated packed form: three or four integers.
    init?(packed values: [Int32]) {
        switch values.count {
        case 3: self.init(startLine: Int(values[0]), startCharacter: Int(values[1]), endLine: Int(values[0]), endCharacter: Int(values[2]))
        case 4: self.init(startLine: Int(values[0]), startCharacter: Int(values[1]), endLine: Int(values[2]), endCharacter: Int(values[3]))
        default: return nil
        }
    }

    init(startLine: Int, startCharacter: Int, endLine: Int, endCharacter: Int) {
        self.startLine = startLine
        self.startCharacter = startCharacter
        self.endLine = endLine
        self.endCharacter = endCharacter
    }

    var isWellFormed: Bool {
        startLine >= 0 && startCharacter >= 0 && endLine >= startLine
            && (endLine > startLine || endCharacter >= startCharacter)
    }
}

struct SCIPOccurrence: Sendable {
    var range: SCIPRange?
    var symbol = ""
    var symbolRoles: Int32 = 0
    var enclosingRange: SCIPRange?

    var isDefinition: Bool { symbolRoles & SCIPSymbolRole.definition != 0 }
    var isImport: Bool { symbolRoles & SCIPSymbolRole.import != 0 }
    var isForwardDefinition: Bool { symbolRoles & SCIPSymbolRole.forwardDefinition != 0 }
}

enum SCIPSymbolRole {
    static let definition: Int32 = 0x1
    static let `import`: Int32 = 0x2
    static let writeAccess: Int32 = 0x4
    static let readAccess: Int32 = 0x8
    static let generated: Int32 = 0x10
    static let test: Int32 = 0x20
    static let forwardDefinition: Int32 = 0x40
}

struct SCIPSymbolInformation: Sendable {
    var symbol = ""
    var documentation: [String] = []
    var relationships: [SCIPRelationship] = []
    var kind = 0
    var displayName = ""
    var signature = ""
    var enclosingSymbol = ""
}

struct SCIPRelationship: Sendable, Equatable {
    var symbol = ""
    var isReference = false
    var isImplementation = false
    var isTypeDefinition = false
    var isDefinition = false
}

/// Streams an `index.scip` file into `SCIPIndex`, skipping unknown fields.
enum SCIPDecoder {
    enum Failure: LocalizedError {
        case notAnIndex(String)
        var errorDescription: String? {
            switch self { case .notAnIndex(let detail): "The SCIP index could not be decoded: \(detail)" }
        }
    }

    static func decode(_ data: Data) throws -> SCIPIndex {
        do {
            var reader = ProtobufReader(data)
            var index = SCIPIndex()
            while let (field, wire) = try reader.readTag() {
                try Task.checkCancellation()
                switch (field, wire) {
                case (1, .lengthDelimited): index.metadata = try metadata(try reader.readMessage())
                case (2, .lengthDelimited): index.documents.append(try document(try reader.readMessage()))
                case (3, .lengthDelimited): index.externalSymbols.append(try symbolInformation(try reader.readMessage()))
                default: try reader.skip(wire)
                }
            }
            return index
        } catch let failure as ProtobufReader.Failure {
            throw Failure.notAnIndex(String(describing: failure))
        }
    }

    private static func metadata(_ message: ProtobufReader) throws -> SCIPMetadata {
        var reader = message
        var metadata = SCIPMetadata()
        while let (field, wire) = try reader.readTag() {
            switch (field, wire) {
            case (2, .lengthDelimited):
                var tool = try reader.readMessage()
                while let (toolField, toolWire) = try tool.readTag() {
                    switch (toolField, toolWire) {
                    case (1, .lengthDelimited): metadata.toolName = try tool.readString()
                    case (2, .lengthDelimited): metadata.toolVersion = try tool.readString()
                    case (3, .lengthDelimited): metadata.toolArguments.append(try tool.readString())
                    default: try tool.skip(toolWire)
                    }
                }
            case (3, .lengthDelimited): metadata.projectRoot = try reader.readString()
            case (4, .varint): metadata.textDocumentEncoding = Int(try reader.readInt32())
            default: try reader.skip(wire)
            }
        }
        return metadata
    }

    private static func document(_ message: ProtobufReader) throws -> SCIPDocument {
        var reader = message
        var document = SCIPDocument()
        while let (field, wire) = try reader.readTag() {
            switch (field, wire) {
            case (1, .lengthDelimited): document.relativePath = try reader.readString()
            case (2, .lengthDelimited): document.occurrences.append(try occurrence(try reader.readMessage()))
            case (3, .lengthDelimited): document.symbols.append(try symbolInformation(try reader.readMessage()))
            case (4, .lengthDelimited): document.language = try reader.readString()
            case (6, .varint): document.positionEncoding = Int(try reader.readInt32())
            default: try reader.skip(wire)
            }
        }
        return document
    }

    private static func occurrence(_ message: ProtobufReader) throws -> SCIPOccurrence {
        var reader = message
        var occurrence = SCIPOccurrence()
        var packedRange: [Int32] = []
        var packedEnclosing: [Int32] = []
        var typedRange: SCIPRange?
        var typedEnclosing: SCIPRange?
        while let (field, wire) = try reader.readTag() {
            switch (field, wire) {
            case (1, _): try reader.readRepeatedInt32(wire: wire, into: &packedRange)
            case (2, .lengthDelimited): occurrence.symbol = try reader.readString()
            case (3, .varint): occurrence.symbolRoles = try reader.readInt32()
            case (7, _): try reader.readRepeatedInt32(wire: wire, into: &packedEnclosing)
            case (8, .lengthDelimited): typedRange = try singleLineRange(try reader.readMessage())
            case (9, .lengthDelimited): typedRange = try multiLineRange(try reader.readMessage())
            case (10, .lengthDelimited): typedEnclosing = try singleLineRange(try reader.readMessage())
            case (11, .lengthDelimited): typedEnclosing = try multiLineRange(try reader.readMessage())
            default: try reader.skip(wire)
            }
        }
        // Typed ranges take precedence over the deprecated packed form.
        occurrence.range = typedRange ?? SCIPRange(packed: packedRange)
        occurrence.enclosingRange = typedEnclosing ?? SCIPRange(packed: packedEnclosing)
        return occurrence
    }

    private static func singleLineRange(_ message: ProtobufReader) throws -> SCIPRange {
        var reader = message
        var line = 0, start = 0, end = 0
        while let (field, wire) = try reader.readTag() {
            switch (field, wire) {
            case (1, .varint): line = Int(try reader.readInt32())
            case (2, .varint): start = Int(try reader.readInt32())
            case (3, .varint): end = Int(try reader.readInt32())
            default: try reader.skip(wire)
            }
        }
        return SCIPRange(startLine: line, startCharacter: start, endLine: line, endCharacter: end)
    }

    private static func multiLineRange(_ message: ProtobufReader) throws -> SCIPRange {
        var reader = message
        var range = SCIPRange(startLine: 0, startCharacter: 0, endLine: 0, endCharacter: 0)
        while let (field, wire) = try reader.readTag() {
            switch (field, wire) {
            case (1, .varint): range.startLine = Int(try reader.readInt32())
            case (2, .varint): range.startCharacter = Int(try reader.readInt32())
            case (3, .varint): range.endLine = Int(try reader.readInt32())
            case (4, .varint): range.endCharacter = Int(try reader.readInt32())
            default: try reader.skip(wire)
            }
        }
        return range
    }

    private static func symbolInformation(_ message: ProtobufReader) throws -> SCIPSymbolInformation {
        var reader = message
        var info = SCIPSymbolInformation()
        while let (field, wire) = try reader.readTag() {
            switch (field, wire) {
            case (1, .lengthDelimited): info.symbol = try reader.readString()
            case (3, .lengthDelimited): info.documentation.append(try reader.readString())
            case (4, .lengthDelimited): info.relationships.append(try relationship(try reader.readMessage()))
            case (5, .varint): info.kind = Int(try reader.readInt32())
            case (6, .lengthDelimited): info.displayName = try reader.readString()
            case (7, .lengthDelimited):
                // `Signature` (historically a `Document`): only `text` (field 5) is used.
                var signature = try reader.readMessage()
                while let (signatureField, signatureWire) = try signature.readTag() {
                    if signatureField == 5, signatureWire == .lengthDelimited {
                        info.signature = try signature.readString()
                    } else {
                        try signature.skip(signatureWire)
                    }
                }
            case (8, .lengthDelimited): info.enclosingSymbol = try reader.readString()
            default: try reader.skip(wire)
            }
        }
        return info
    }

    private static func relationship(_ message: ProtobufReader) throws -> SCIPRelationship {
        var reader = message
        var relationship = SCIPRelationship()
        while let (field, wire) = try reader.readTag() {
            switch (field, wire) {
            case (1, .lengthDelimited): relationship.symbol = try reader.readString()
            case (2, .varint): relationship.isReference = try reader.readBool()
            case (3, .varint): relationship.isImplementation = try reader.readBool()
            case (4, .varint): relationship.isTypeDefinition = try reader.readBool()
            case (5, .varint): relationship.isDefinition = try reader.readBool()
            default: try reader.skip(wire)
            }
        }
        return relationship
    }
}
