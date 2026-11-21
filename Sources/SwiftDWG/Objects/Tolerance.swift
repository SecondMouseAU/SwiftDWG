// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readTolerance). See NOTICE.md. The field order is the format's own, from the Open Design
// Specification for .dwg files.

import SwiftDXF

/// The fields of a TOLERANCE entity, a geometric tolerance (a feature control frame), in the
/// file's own terms: points and directions in the entity's own coordinate system.
struct ToleranceData: Equatable {
    /// Where the frame is placed (DXF 10, 20, 30).
    var insertion = DXF.Point(0, 0, 0)
    /// The direction the frame's text runs in (DXF 11, 21, 31).
    var direction = DXF.Point(1, 0, 0)
    /// The normal of the plane the frame lies in (DXF 210, 220, 230).
    var extrusion = DXF.Point(0, 0, 1)
    /// The frame as AutoCAD's own markup writes it (DXF 1), such as `{\Fgdt;i}%%v0.012%%v%%vB`.
    ///
    /// Lines are separated by a line feed, and `%%v` is the rule between two boxes of a row.
    var text = ""
    /// The handle of the dimension style that sizes the frame (DXF 3 names it).
    var style: UInt64 = 0
}

extension ObjectReader {
    /// Reads a tolerance.
    mutating func readTolerance() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var tolerance = ToleranceData()

        if version <= .ac1014 {
            // A short that is not used, the height of the frame, and DIMGAP at the time the
            // frame was made times the dimension scale. DXF has no group for any of them.
            _ = try main.readBitShort()
            _ = try main.readBitDouble()
            _ = try main.readBitDouble()
        }
        tolerance.insertion = DXF.Point(fromBits: try main.read3BitDouble())
        tolerance.direction = DXF.Point(fromBits: try main.read3BitDouble())
        // Always three bit doubles, never the one-bit form of an extrusion elsewhere.
        tolerance.extrusion = DXF.Point(fromBits: try main.read3BitDouble())
        tolerance.text = try readText()

        tolerance.style = try readOwnHandle()
        return DecodedEntity(common: common, geometry: .tolerance(tolerance))
    }
}
