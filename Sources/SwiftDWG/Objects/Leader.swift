// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readLeader). See NOTICE.md. The field order is the format's own, from the Open Design
// Specification for .dwg files.

import SwiftDXF

/// The fields of a leader entity, in the file's own terms: points and directions in the entity's
/// own coordinate system.
struct LeaderData {
    /// What the leader points at (DXF 73): 0 text, 1 tolerance, 2 block reference, 3 nothing.
    var annotationType = 3
    /// 0 for straight segments, 1 for a spline (DXF 72).
    var pathType = 0
    /// The vertices of the leader, from the arrow end (DXF 10).
    ///
    /// The file keeps no vertex for the hook line: AutoCAD adds one before the last vertex when it
    /// writes DXF, and sets DXF 75.
    var vertices: [DXF.Point] = []
    /// The origin of the leader's plane, which by default is the first vertex.
    var origin = DXF.Point(0, 0, 0)
    /// The extrusion (DXF 210).
    var extrusion = DXF.Point(0, 0, 1)
    /// The horizontal direction of the leader's plane (DXF 211).
    var horizontalDirection = DXF.Point(1, 0, 0)
    /// The offset to the insertion point of a block annotation (DXF 212).
    var blockOffset = DXF.Point(0, 0, 0)
    /// The offset from the last vertex to the annotation of a leader that is not planar (DXF 213),
    /// kept from R14.
    var annotationOffset: DXF.Point?
    /// The height of the annotation's text box (DXF 40), kept until R2007.
    ///
    /// Later files hold the size in the annotation.
    var textHeight: Double?
    /// The width of the annotation's text box (DXF 41), kept until R2007.
    var textWidth: Double?
    /// Whether the hook line runs along the horizontal direction and not against it (DXF 74).
    var hookLineOnHorizontalDirection = false
    /// Whether the leader has an arrow head (DXF 71).
    var hasArrowHead = false
    /// DIMGAP at the time the leader was made, times the dimension scale, in R13 and R14 only.
    var dimensionGap: Double?
    /// The arrow head type of R13 and R14 leaders.
    var arrowHeadType: Int?
    /// DIMASZ at the time the leader was made, times the dimension scale, in R13 and R14 only.
    var arrowSize: Double?
    /// The handle of the annotation the leader belongs to (DXF 340), or 0.
    var annotation: UInt64 = 0
    /// The handle of the dimension style (DXF 3 names it).
    var style: UInt64 = 0
}

extension DXF.Point {
    fileprivate init(_ triple: (x: Double, y: Double, z: Double)) {
        self.init(triple.x, triple.y, triple.z)
    }
}

extension ObjectReader {
    /// Reads a leader.
    mutating func readLeader() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var leader = LeaderData()

        _ = try main.readBit()  // seems always to be 0
        leader.annotationType = Int(try main.readBitShort())
        leader.pathType = Int(try main.readBitShort())

        let count = try DimensionsSupport.boundedCount(
            try main.readBitLong(), bitsEach: 6, in: self, what: "leader vertices")
        for _ in 0..<count { leader.vertices.append(DXF.Point(try main.read3BitDouble())) }

        leader.origin = DXF.Point(try main.read3BitDouble())
        leader.extrusion = DXF.Point(try main.read3BitDouble())
        leader.horizontalDirection = DXF.Point(try main.read3BitDouble())
        leader.blockOffset = DXF.Point(try main.read3BitDouble())
        if version >= .ac1014 { leader.annotationOffset = DXF.Point(try main.read3BitDouble()) }
        let isR13OrR14 = version <= .ac1014
        if isR13OrR14 { leader.dimensionGap = try main.readBitDouble() }

        // R2010 and later do not keep the size of the text box here (ACadSharp warns that reading
        // it gives wrong values, and the handles after it only line up without it).
        if version <= .ac1021 {
            leader.textHeight = try main.readBitDouble()
            leader.textWidth = try main.readBitDouble()
        }
        leader.hookLineOnHorizontalDirection = try main.readBit()
        leader.hasArrowHead = try main.readBit()

        if isR13OrR14 {
            leader.arrowHeadType = Int(try main.readBitShort())
            leader.arrowSize = try main.readBitDouble()
            _ = try main.readBit()
            _ = try main.readBit()
            _ = try main.readBitShort()
            _ = try main.readBitShort()  // the colour used when the dimension colour is by block
            _ = try main.readBit()
            _ = try main.readBit()
        }
        if version >= .ac1015 {
            _ = try main.readBitShort()
            _ = try main.readBit()
            _ = try main.readBit()
        }

        leader.annotation = try readOwnHandle()
        leader.style = try readOwnHandle()
        return DecodedEntity(common: common, geometry: .leader(leader))
    }
}
