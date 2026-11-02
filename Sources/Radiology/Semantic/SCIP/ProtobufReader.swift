import Foundation

/// A minimal protobuf wire-format reader: enough to walk SCIP indexes without
/// generated code or a protobuf dependency. Unknown fields are skipped, so
/// indexers that use newer or older schema revisions still decode.
struct ProtobufReader {
    enum WireType: Int {
        case varint = 0, fixed64 = 1, lengthDelimited = 2, startGroup = 3, endGroup = 4, fixed32 = 5
    }

    enum Failure: Error, Equatable {
        case truncated
        case malformedVarint
        case unsupportedWireType(Int)
        case tooDeep
    }

    private let bytes: Data
    private(set) var offset: Int
    private let end: Int

    init(_ data: Data) {
        bytes = data
        offset = data.startIndex
        end = data.endIndex
    }

    private init(_ data: Data, range: Range<Int>) {
        bytes = data
        offset = range.lowerBound
        end = range.upperBound
    }

    var isAtEnd: Bool { offset >= end }

    mutating func readTag() throws -> (field: Int, wire: WireType)? {
        guard !isAtEnd else { return nil }
        let key = try readVarint()
        let rawWire = Int(key & 0x7)
        guard let wire = WireType(rawValue: rawWire), wire != .startGroup, wire != .endGroup else {
            throw Failure.unsupportedWireType(rawWire)
        }
        return (Int(key >> 3), wire)
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard offset < end else { throw Failure.truncated }
            let byte = bytes[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { throw Failure.malformedVarint }
        }
    }

    mutating func readInt32() throws -> Int32 { Int32(truncatingIfNeeded: try readVarint()) }
    mutating func readBool() throws -> Bool { try readVarint() != 0 }

    mutating func readBytes() throws -> Data {
        let length = Int(try readVarint())
        guard length >= 0, offset + length <= end else { throw Failure.truncated }
        defer { offset += length }
        return bytes.subdata(in: offset..<offset + length)
    }

    mutating func readString() throws -> String {
        String(decoding: try readBytes(), as: UTF8.self)
    }

    /// A reader over an embedded message's bytes, without copying.
    mutating func readMessage() throws -> ProtobufReader {
        let length = Int(try readVarint())
        guard length >= 0, offset + length <= end else { throw Failure.truncated }
        defer { offset += length }
        return ProtobufReader(bytes, range: offset..<offset + length)
    }

    /// Packed or unpacked repeated int32 values share one field number; both
    /// forms append here.
    mutating func readRepeatedInt32(wire: WireType, into values: inout [Int32]) throws {
        switch wire {
        case .lengthDelimited:
            var packed = try readMessage()
            while !packed.isAtEnd { values.append(try packed.readInt32()) }
        case .varint:
            values.append(try readInt32())
        default:
            try skip(wire)
        }
    }

    mutating func skip(_ wire: WireType) throws {
        switch wire {
        case .varint: _ = try readVarint()
        case .fixed64: try advance(8)
        case .fixed32: try advance(4)
        case .lengthDelimited: _ = try readBytes()
        case .startGroup, .endGroup: throw Failure.unsupportedWireType(wire.rawValue)
        }
    }

    private mutating func advance(_ count: Int) throws {
        guard offset + count <= end else { throw Failure.truncated }
        offset += count
    }
}
