// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readCommonDimensionData, readCommonDimensionAlignedData, readCommonDimensionHandles,
// readDimLinear, readDimAligned, readDimAngular3pt, readDimLine2pt, readDimRadius,
// readDimDiameter, readDimOrdinate). See NOTICE.md. The field order is the format's own, from the
// Open Design Specification for .dwg files. Unlike ACadSharp, this keeps the actual measurement,
// the insertion scale and rotation, and the flag bits that make up the DXF type code.

import SwiftDXF

/// The seven kinds of dimension, numbered as the low bits of the DXF type code (group 70).
enum DimensionKind: Int {
    /// A horizontal, vertical or rotated dimension.
    case linear = 0
    case aligned = 1
    /// An angle between two lines.
    case angular2Line = 2
    case diameter = 3
    case radius = 4
    /// An angle from a vertex and two points.
    case angular3Point = 5
    case ordinate = 6

    /// The kind of dimension that has this object type code, or `nil` for another object.
    init?(objectType: Int) {
        switch objectType {
        case ObjectType.dimensionLinear: self = .linear
        case ObjectType.dimensionAligned: self = .aligned
        case ObjectType.dimensionAngular2Line: self = .angular2Line
        case ObjectType.dimensionDiameter: self = .diameter
        case ObjectType.dimensionRadius: self = .radius
        case ObjectType.dimensionAngular3Point: self = .angular3Point
        case ObjectType.dimensionOrdinate: self = .ordinate
        default: return nil
        }
    }
}

/// The fields of a dimension entity, in the file's own terms: angles in radians, points in the
/// entity's own coordinate system.
///
/// The definition points are named by the DXF group they correspond to, and which of them a
/// dimension has depends on its kind:
///
/// - Linear and aligned: `definitionPoint` is on the dimension line, `firstPoint` and
///   `secondPoint` are the origins of the extension lines.
/// - Angular from 3 points: `definitionPoint` is on the dimension arc, `firstPoint` and
///   `secondPoint` end the two arms, `vertexPoint` is the vertex.
/// - Angular from 2 lines: `firstPoint` and `secondPoint` are the ends of the first line,
///   `vertexPoint` is the start of the second line and `definitionPoint` its end, `arcPoint` is on
///   the dimension arc.
/// - Radius: `definitionPoint` is the centre and `vertexPoint` is on the circle.
/// - Diameter: `vertexPoint` and `definitionPoint` are the two ends of the diameter.
/// - Ordinate: `definitionPoint` is the origin, `firstPoint` the feature location and
///   `secondPoint` the end of the leader.
///
/// The text mid point, the insertion point and `arcPoint` are in the entity's coordinate system
/// (ECS), and take their z value from the dimension's elevation.
struct DimensionData {
    var kind: DimensionKind
    /// The type code as DXF group 70 composes it: the kind, 32 for a dimension that has its own
    /// anonymous block, 64 for an ordinate dimension of the X datum, and 128 when the text has
    /// been moved from its default place.
    var typeFlags: Int
    /// The handle of the dimension style.
    var style: UInt64 = 0
    /// The handle of the anonymous block record that draws the dimension.
    var block: UInt64 = 0
    /// The extrusion (DXF 210).
    var extrusion = DXF.Point(0, 0, 1)
    /// The version byte of R2010 and later (DXF 280), or `nil` before.
    var formatVersion: Int?

    var definitionPoint = DXF.Point(0, 0, 0)
    var firstPoint: DXF.Point?
    var secondPoint: DXF.Point?
    var vertexPoint: DXF.Point?
    var arcPoint: DXF.Point?
    /// The middle of the dimension text (DXF 11).
    var textMidPoint = DXF.Point(0, 0, 0)
    /// The insertion point for a clone of the dimension (DXF 12).
    var insertionPoint = DXF.Point(0, 0, 0)

    /// The text the user typed (DXF 1), empty when the text is the measurement.
    var text = ""
    /// The rotation of the text (DXF 53).
    var textRotation = 0.0
    /// The direction of the horizontal for the dimension (DXF 51).
    var horizontalDirection = 0.0
    /// The measurement the dimension holds (DXF 42), or `nil` before R2000.
    var measurement: Double?

    /// The scale of the insertion of the anonymous block, which the format keeps and DXF mostly
    /// does not show.
    var insertionScale = DXF.Point(1, 1, 1)
    /// The rotation of the insertion of the anonymous block (DXF 54).
    var insertionRotation = 0.0

    /// The attachment point of the text (DXF 71), or `nil` before R2000.
    var attachmentPoint: Int?
    /// The line spacing style (DXF 72), or `nil` before R2000.
    var lineSpacingStyle: Int?
    /// The line spacing factor (DXF 41), or `nil` before R2000.
    var lineSpacingFactor: Double?
    /// Whether the first arrow is flipped (DXF 74), kept from R2007.
    var flipArrow1 = false
    /// Whether the second arrow is flipped (DXF 75), kept from R2007.
    var flipArrow2 = false

    /// The rotation of the extension lines, which makes a dimension oblique (DXF 52), for linear
    /// and aligned dimensions only.
    var extLineRotation: Double?
    /// The rotation of the dimension line (DXF 50), for linear dimensions only.
    var rotation: Double?
    /// The length of the leader (DXF 40), for radius and diameter dimensions only.
    var leaderLength: Double?

    /// Whether the text was placed by hand and is not at its default place.
    var isTextUserDefinedLocation: Bool { typeFlags & 128 != 0 }
    /// Whether an ordinate dimension measures from the X datum, and so is of the X type.
    var isOrdinateTypeX: Bool { kind == .ordinate && typeFlags & 64 != 0 }
}

extension DXF.Point {
    fileprivate init(_ triple: (x: Double, y: Double, z: Double)) {
        self.init(triple.x, triple.y, triple.z)
    }
}

extension ObjectReader {
    /// Reads a dimension of whichever of the seven kinds this object is.
    mutating func readDimension() throws -> DecodedEntity {
        guard let kind = DimensionKind(objectType: type) else {
            throw DWG.Error.invalid("object type \(type) is not a dimension")
        }
        let (common, shared) = try readCommonDimensionData(kind: kind)
        var dimension = shared
        // The ECS points share the elevation, which was stored with the text mid point.
        let elevation = dimension.textMidPoint.z

        switch kind {
        case .linear:
            try readAlignedDimensionData(into: &dimension)
            dimension.rotation = try main.readBitDouble()
        case .aligned:
            try readAlignedDimensionData(into: &dimension)
        case .angular3Point:
            dimension.definitionPoint = DXF.Point(try main.read3BitDouble())
            dimension.firstPoint = DXF.Point(try main.read3BitDouble())
            dimension.secondPoint = DXF.Point(try main.read3BitDouble())
            dimension.vertexPoint = DXF.Point(try main.read3BitDouble())
        case .angular2Line:
            let arc = try main.read2RawDouble()
            dimension.arcPoint = DXF.Point(arc.x, arc.y, elevation)
            dimension.firstPoint = DXF.Point(try main.read3BitDouble())
            dimension.secondPoint = DXF.Point(try main.read3BitDouble())
            dimension.vertexPoint = DXF.Point(try main.read3BitDouble())
            dimension.definitionPoint = DXF.Point(try main.read3BitDouble())
        case .radius:
            dimension.definitionPoint = DXF.Point(try main.read3BitDouble())
            dimension.vertexPoint = DXF.Point(try main.read3BitDouble())
            dimension.leaderLength = try main.readBitDouble()
        case .diameter:
            dimension.vertexPoint = DXF.Point(try main.read3BitDouble())
            dimension.definitionPoint = DXF.Point(try main.read3BitDouble())
            dimension.leaderLength = try main.readBitDouble()
        case .ordinate:
            dimension.definitionPoint = DXF.Point(try main.read3BitDouble())
            dimension.firstPoint = DXF.Point(try main.read3BitDouble())
            dimension.secondPoint = DXF.Point(try main.read3BitDouble())
            // Bit 0 says the dimension measures from the X datum.
            if try main.readByte() & 1 != 0 { dimension.typeFlags |= 64 }
        }

        // The dimension's own two handles come after the common handles of the entity.
        dimension.style = try readOwnHandle()
        dimension.block = try readOwnHandle()
        return DecodedEntity(common: common, geometry: .dimension(dimension))
    }

    /// Reads the entity data and the fields that every kind of dimension has.
    ///
    /// - Returns: The entity data, and the dimension so far.
    fileprivate mutating func readCommonDimensionData(kind: DimensionKind) throws -> (
        EntityCommon, DimensionData
    ) {
        let common = try readEntityCommon()
        var data = DimensionData(kind: kind, typeFlags: kind.rawValue)

        if version >= .ac1024 { data.formatVersion = Int(try main.readByte()) }
        data.extrusion = DXF.Point(try main.read3BitDouble())

        // The ECS points (text mid point, insertion point, arc point) share one elevation, which
        // is stored after the first of them.
        let middle = try main.read2RawDouble()
        let elevation = try main.readBitDouble()
        data.textMidPoint = DXF.Point(middle.x, middle.y, elevation)

        // Bit 0 is the opposite of 128 in the DXF type code (text moved by hand); bit 1 is 32
        // (the dimension has an anonymous block).
        let flags = try main.readByte()
        if flags & 1 == 0 { data.typeFlags |= 128 }
        if flags & 2 != 0 { data.typeFlags |= 32 }

        data.text = try readText()
        data.textRotation = try main.readBitDouble()
        data.horizontalDirection = try main.readBitDouble()

        // The scale and rotation of the insertion of the anonymous block.
        data.insertionScale = DXF.Point(
            try main.readBitDouble(), try main.readBitDouble(), try main.readBitDouble())
        data.insertionRotation = try main.readBitDouble()

        if version >= .ac1015 {
            data.attachmentPoint = Int(try main.readBitShort())
            data.lineSpacingStyle = Int(try main.readBitShort())
            data.lineSpacingFactor = try main.readBitDouble()
            data.measurement = try main.readBitDouble()
        }
        if version >= .ac1021 {
            _ = try main.readBit()  // not understood
            data.flipArrow1 = try main.readBit()
            data.flipArrow2 = try main.readBit()
        }

        let insertion = try main.read2RawDouble()
        data.insertionPoint = DXF.Point(insertion.x, insertion.y, elevation)
        return (common, data)
    }

    /// Reads the points and the extension line rotation that linear and aligned dimensions share.
    fileprivate mutating func readAlignedDimensionData(into data: inout DimensionData) throws {
        data.firstPoint = DXF.Point(try main.read3BitDouble())
        data.secondPoint = DXF.Point(try main.read3BitDouble())
        data.definitionPoint = DXF.Point(try main.read3BitDouble())
        data.extLineRotation = try main.readBitDouble()
    }
}
