// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readLine, readCircle, readArc, readPoint). See NOTICE.md. The field order is the format's own,
// from the Open Design Specification for .dwg files.

import SwiftDXF

/// The geometry of an entity, in the file's own terms: angles in radians, points and normals in
/// the entity's own coordinate system.
enum EntityGeometry {
    case line(start: DXF.Point, end: DXF.Point, thickness: Double, extrusion: DXF.Point)
    case circle(center: DXF.Point, radius: Double, thickness: Double, extrusion: DXF.Point)
    case arc(
        center: DXF.Point, radius: Double, thickness: Double, extrusion: DXF.Point,
        startAngle: Double, endAngle: Double)
    case point(
        location: DXF.Point, thickness: Double, extrusion: DXF.Point, rotation: Double)
    // The families below are decoded in their own files (Text.swift, Insert.swift, Curves.swift,
    // Polylines.swift, Surfaces.swift, Dimensions.swift, Leader.swift, Hatch.swift).
    case text(TextData)
    case mtext(MTextData)
    case insert(InsertData)
    case ellipse(EllipseData)
    case spline(SplineData)
    case lwpolyline(LWPolylineData)
    case polyline2D(Polyline2DData)
    case polyline3D(Polyline3DData)
    case vertex2D(Vertex2DData)
    case vertex3D(Vertex3DData)
    case seqend
    case block(BlockData)
    case endBlock
    case solid(SolidData)
    case face3D(Face3DData)
    case dimension(DimensionData)
    case leader(LeaderData)
    case hatch(HatchData)
}

/// An entity read from the file: what every entity has, and its geometry.
struct DecodedEntity {
    var common: EntityCommon
    var geometry: EntityGeometry
}

extension DXF.Point {
    fileprivate init(_ triple: (x: Double, y: Double, z: Double)) {
        self.init(triple.x, triple.y, triple.z)
    }
}

extension ObjectReader {
    mutating func readLine() throws -> DecodedEntity {
        let common = try readEntityCommon()
        let start: DXF.Point
        let end: DXF.Point
        if version <= .ac1014 {
            start = DXF.Point(try main.read3BitDouble())
            end = DXF.Point(try main.read3BitDouble())
        } else {
            // One bit says the z values are zero; the end point's x and y use the start's as
            // their defaults.
            let flat = try main.readBit()
            let startX = try main.readRawDouble()
            let endX = try main.readBitDouble(default: startX)
            let startY = try main.readRawDouble()
            let endY = try main.readBitDouble(default: startY)
            var startZ = 0.0
            var endZ = 0.0
            if !flat {
                startZ = try main.readRawDouble()
                endZ = try main.readBitDouble(default: startZ)
            }
            start = DXF.Point(startX, startY, startZ)
            end = DXF.Point(endX, endY, endZ)
        }
        let thickness = try main.readBitThickness()
        let extrusion = DXF.Point(try main.readBitExtrusion())
        return DecodedEntity(
            common: common,
            geometry: .line(start: start, end: end, thickness: thickness, extrusion: extrusion))
    }

    mutating func readCircle() throws -> DecodedEntity {
        let common = try readEntityCommon()
        let center = DXF.Point(try main.read3BitDouble())
        let radius = try main.readBitDouble()
        let thickness = try main.readBitThickness()
        let extrusion = DXF.Point(try main.readBitExtrusion())
        return DecodedEntity(
            common: common,
            geometry: .circle(
                center: center, radius: radius, thickness: thickness, extrusion: extrusion))
    }

    mutating func readArc() throws -> DecodedEntity {
        let common = try readEntityCommon()
        let center = DXF.Point(try main.read3BitDouble())
        let radius = try main.readBitDouble()
        let thickness = try main.readBitThickness()
        let extrusion = DXF.Point(try main.readBitExtrusion())
        let start = try main.readBitDouble()
        let end = try main.readBitDouble()
        return DecodedEntity(
            common: common,
            geometry: .arc(
                center: center, radius: radius, thickness: thickness, extrusion: extrusion,
                startAngle: start, endAngle: end))
    }

    mutating func readPoint() throws -> DecodedEntity {
        let common = try readEntityCommon()
        let location = DXF.Point(try main.read3BitDouble())
        let thickness = try main.readBitThickness()
        let extrusion = DXF.Point(try main.readBitExtrusion())
        let rotation = try main.readBitDouble()
        return DecodedEntity(
            common: common,
            geometry: .point(
                location: location, thickness: thickness, extrusion: extrusion, rotation: rotation))
    }

    /// Reads the entity of this object's type, or `nil` for a type that is not decoded yet.
    mutating func readEntity() throws -> DecodedEntity? {
        switch type {
        case ObjectType.line: return try readLine()
        case ObjectType.circle: return try readCircle()
        case ObjectType.arc: return try readArc()
        case ObjectType.point: return try readPoint()
        case ObjectType.text: return try readTextEntity()
        case ObjectType.mtext: return try readMText()
        case ObjectType.insert: return try readInsert()
        case ObjectType.minsert: return try readMInsert()
        case ObjectType.ellipse: return try readEllipse()
        case ObjectType.spline: return try readSpline()
        case ObjectType.lwpolyline: return try readLWPolyline()
        case ObjectType.polyline2D: return try readPolyline2D()
        case ObjectType.polyline3D: return try readPolyline3D()
        case ObjectType.vertex2D: return try readVertex2D()
        case ObjectType.vertex3D: return try readVertex3D()
        case ObjectType.seqend: return try readSeqend()
        case ObjectType.block: return try readBlock()
        case ObjectType.endBlock: return try readEndBlock()
        case ObjectType.solid, ObjectType.trace: return try readSolid()
        case ObjectType.face3D: return try readFace3D()
        case ObjectType.dimensionOrdinate, ObjectType.dimensionLinear,
            ObjectType.dimensionAligned, ObjectType.dimensionAngular3Point,
            ObjectType.dimensionAngular2Line, ObjectType.dimensionRadius,
            ObjectType.dimensionDiameter:
            return try readDimension()
        case ObjectType.leader: return try readLeader()
        case ObjectType.hatch: return try readHatch()
        default: return nil
        }
    }
}
