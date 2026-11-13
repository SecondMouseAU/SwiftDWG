// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readSolid, read3dFace). See NOTICE.md. The field order is the format's own, from the Open
// Design Specification for .dwg files.

import SwiftDXF

/// A 2D solid or a trace: a filled quadrilateral in the entity's own coordinate system.
///
/// The two share one layout. `isTrace` says which a file means.
struct SolidData {
    /// The four corners in the order the file gives them, each at the elevation.
    var corners: [DXF.Point]
    var thickness: Double
    /// The z of every corner.
    var elevation: Double
    var extrusion: DXF.Point
    /// Whether the entity is a trace and not a solid.
    var isTrace: Bool
}

/// A 3D face: four corners in the world coordinate system, and which edges are not drawn.
struct Face3DData {
    /// The four corners in the order the file gives them.
    var corners: [DXF.Point]
    /// The invisible edge flags: bit 0 for the edge from the first corner to the second, bit 1 for
    /// the second to the third, bit 2 for the third to the fourth, bit 3 for the fourth to the
    /// first. 0 when every edge is drawn.
    var invisibleEdges: Int
}

extension ObjectReader {
    mutating func readSolid() throws -> DecodedEntity {
        let common = try readEntityCommon()
        let thickness = try main.readBitThickness()
        let elevation = try main.readBitDouble()
        var corners: [DXF.Point] = []
        for _ in 0..<4 {
            let corner = try main.read2RawDouble()
            corners.append(DXF.Point(corner.x, corner.y, elevation))
        }
        let extrusion = DXF.Point(fromBits: try main.readBitExtrusion())
        return DecodedEntity(
            common: common,
            geometry: .solid(
                SolidData(
                    corners: corners, thickness: thickness, elevation: elevation,
                    extrusion: extrusion, isTrace: type == ObjectType.trace)))
    }

    mutating func readFace3D() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var corners: [DXF.Point] = []
        var flags = 0
        if version <= .ac1014 {
            for _ in 0..<4 { corners.append(DXF.Point(fromBits: try main.read3BitDouble())) }
            flags = try readFlagsWord()
        } else {
            // One bit says no flags follow, and one that the first corner's z is zero. Each
            // corner after the first uses the corner before it as the default for its values.
            let hasNoFlags = try main.readBit()
            let flat = try main.readBit()
            let x = try main.readRawDouble()
            let y = try main.readRawDouble()
            let z = try flat ? 0.0 : main.readRawDouble()
            var corner = (x: x, y: y, z: z)
            corners.append(DXF.Point(fromBits: corner))
            for _ in 1..<4 {
                corner = try main.read3BitDouble(default: corner)
                corners.append(DXF.Point(fromBits: corner))
            }
            if !hasNoFlags { flags = try readFlagsWord() }
        }
        return DecodedEntity(
            common: common,
            geometry: .face3D(Face3DData(corners: corners, invisibleEdges: flags)))
    }
}
