// The extended data item codes and layouts are the format's own, from the Open Design
// Specification for .dwg files; ACadSharp's DwgObjectReader.readExtendedDataRecords (MIT) was
// the reference for the layout of each. See NOTICE.md.

import Foundation

/// One group of extended data (XDATA), as DXF writes it.
struct ExtendedDataGroup: Equatable {
    enum Value: Equatable {
        case string(String)
        case integer(Int)
        case real(Double)
    }

    var code: Int
    var value: Value
}

enum ExtendedDataDecoder {
    /// The groups of one application's extended data, in order.
    ///
    /// Data it cannot make sense of ends the list: what was read before it is kept.
    static func groups(
        _ bytes: [UInt8], version: DWG.Version, textEncoding: String.Encoding
    ) -> [ExtendedDataGroup] {
        var reader = BitReader(bytes, version: version)
        var out: [ExtendedDataGroup] = []
        while !reader.isAtEnd {
            guard let group = try? next(&reader, version: version, encoding: textEncoding) else {
                break
            }
            out.append(group)
        }
        return out
    }

    private static func next(
        _ reader: inout BitReader, version: DWG.Version, encoding: String.Encoding
    ) throws -> ExtendedDataGroup {
        let code = 1000 + Int(try reader.readByte())
        switch code {
        case 1000, 1001:
            return ExtendedDataGroup(
                code: code, value: .string(try text(&reader, version: version, encoding: encoding)))
        case 1002:
            return ExtendedDataGroup(
                code: code, value: .string(try reader.readByte() == 1 ? "}" : "{"))
        case 1003, 1005:
            var handle: UInt64 = 0
            for _ in 0..<8 { handle = handle << 8 | UInt64(try reader.readByte()) }
            return ExtendedDataGroup(
                code: code, value: .string(String(handle, radix: 16, uppercase: true)))
        case 1004:
            let count = Int(try reader.readByte())
            let hex = try reader.readBytes(count).map { String(format: "%02X", $0) }.joined()
            return ExtendedDataGroup(code: code, value: .string(hex))
        case 1010, 1011, 1012, 1013:
            // A point: written as three groups, the codes 10, 20 and 30 of the base.
            let x = try reader.readRawDouble()
            let y = try reader.readRawDouble()
            let z = try reader.readRawDouble()
            return ExtendedDataGroup(
                code: code, value: .string("\(x)\n\(code + 10)\n\(y)\n\(code + 20)\n\(z)"))
        case 1040, 1041, 1042:
            return ExtendedDataGroup(code: code, value: .real(try reader.readRawDouble()))
        case 1070:
            return ExtendedDataGroup(code: code, value: .integer(Int(try reader.readShort())))
        case 1071:
            return ExtendedDataGroup(code: code, value: .integer(Int(try reader.readRawLong())))
        default:
            throw DWG.Error.invalid("extended data code \(code)")
        }
    }

    /// A string item: from R2007 a count of UTF-16 characters and the characters; before, a count
    /// of bytes, a code page word and the bytes.
    private static func text(
        _ reader: inout BitReader, version: DWG.Version, encoding: String.Encoding
    ) throws -> String {
        if version >= .ac1021 {
            let count = Int(try reader.readUShort())
            var units = [UInt16]()
            for _ in 0..<count { units.append(try reader.readUShort()) }
            return String(decoding: units, as: UTF16.self).replacingOccurrences(of: "\0", with: "")
        }
        let count = Int(try reader.readByte())
        _ = try reader.readUShort()
        let raw = try reader.readBytes(count).prefix { $0 != 0 }
        return String(bytes: raw, encoding: encoding) ?? String(decoding: raw, as: UTF8.self)
    }
}
