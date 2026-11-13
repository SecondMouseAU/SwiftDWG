import SwiftDXF

/// Writes group codes and values as an ASCII DXF.
///
/// SwiftDWG hands what it reads to SwiftDXF as DXF text, so that a drawing that came from a DWG is
/// read by exactly the code that reads one that came from a DXF: the same handling of extrusions,
/// block references, paper space and identities.
struct DXFWriter {
    private(set) var text = ""

    /// Writes one group.
    mutating func group(_ code: Int, _ value: String) {
        text += "\(code)\n\(Self.clean(value))\n"
    }

    mutating func group(_ code: Int, _ value: Int) {
        text += "\(code)\n\(value)\n"
    }

    mutating func group(_ code: Int, _ value: Double) {
        text += "\(code)\n\(Self.format(value))\n"
    }

    /// Writes a handle as upper-case hexadecimal.
    mutating func handle(_ code: Int, _ value: UInt64) {
        text += "\(code)\n\(String(value, radix: 16, uppercase: true))\n"
    }

    /// Writes a point as the three groups `code`, `code + 10` and `code + 20`.
    mutating func point(_ code: Int, _ point: DXF.Point) {
        group(code, point.x)
        group(code + 10, point.y)
        group(code + 20, point.z)
    }

    /// Writes only x and y, for the entities whose z is held apart as an elevation.
    mutating func point2D(_ code: Int, x: Double, y: Double) {
        group(code, x)
        group(code + 10, y)
    }

    /// Starts a record such as a section, a table or an entity: group 0.
    mutating func begin(_ type: String) {
        group(0, type)
    }

    mutating func beginSection(_ name: String) {
        begin("SECTION")
        group(2, name)
    }

    mutating func endSection() {
        begin("ENDSEC")
    }

    mutating func finish() -> String {
        begin("EOF")
        return text
    }

    /// A double the way a DXF writes it, with every digit a reader needs to get it back.
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) + ".0" }
        return "\(value)"
    }

    /// A string as a group value, with control characters written the way AutoCAD's DXF writes
    /// them: as `^` and the character shifted up by 64 (so a line feed is `^J`), and a `^` as
    /// `^ `.
    private static func clean(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { $0.value < 0x20 || $0 == "^" }) else {
            return value
        }
        var out = ""
        for scalar in value.unicodeScalars {
            if scalar == "^" {
                out += "^ "
            } else if scalar.value < 0x20, let shifted = Unicode.Scalar(scalar.value + 64) {
                out += "^" + String(Character(shifted))
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
