// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readHatch) and DwgStreamReaderAC18.cs (ReadCmColor, for the gradient colours). See NOTICE.md.
// The field order is the format's own, from the Open Design Specification for .dwg files.

import SwiftDXF

/// One colour stop of a gradient fill.
struct HatchGradientColor {
    /// Where along the gradient the colour sits, 0 to 1 (DXF 463).
    var position: Double
    var color: DWGColor
}

/// The gradient fill of a hatch, which R2004 and later keep for every hatch.
struct HatchGradient {
    /// Whether the hatch is filled with the gradient (DXF 450 is not 0).
    var isEnabled = false
    /// DXF 451.
    var reserved = 0
    /// The angle of the gradient, in radians (DXF 460).
    var angle = 0.0
    /// The shift of the gradient (DXF 461).
    var shift = 0.0
    /// Whether the gradient has one colour and a tint (DXF 452).
    var isSingleColor = false
    /// The tint of a one-colour gradient (DXF 462).
    var tint = 0.0
    var colors: [HatchGradientColor] = []
    /// The name of the gradient, such as `LINEAR` (DXF 470).
    var name = ""
}

/// A vertex of a polyline boundary path.
struct HatchPolylineVertex {
    var point: DXF.Point2
    /// The tangent of a quarter of the angle of the arc to the next vertex (DXF 42), 0 for a
    /// straight segment.
    var bulge: Double
}

/// A spline edge of a boundary path.
struct HatchSplineEdge {
    var degree = 0
    var isRational = false
    var isPeriodic = false
    var knots: [Double] = []
    var controlPoints: [DXF.Point2] = []
    /// One weight for each control point of a rational spline, otherwise empty.
    var weights: [Double] = []
    /// The fit points, kept from R2010.
    var fitPoints: [DXF.Point2] = []
    var startTangent: DXF.Point2?
    var endTangent: DXF.Point2?
}

/// One edge of a boundary path that is made of edges.
enum HatchEdge {
    case line(start: DXF.Point2, end: DXF.Point2)
    /// Angles in radians.
    case circularArc(
        center: DXF.Point2, radius: Double, startAngle: Double, endAngle: Double,
        counterClockwise: Bool)
    /// `majorAxisEnd` is relative to the centre. Angles in radians.
    case ellipticArc(
        center: DXF.Point2, majorAxisEnd: DXF.Point2, minorToMajorRatio: Double,
        startAngle: Double, endAngle: Double, counterClockwise: Bool)
    case spline(HatchSplineEdge)
}

/// The shape of a boundary path.
enum HatchBoundaryShape {
    /// A closed or open polyline, with bulges when `hasBulges` is set.
    case polyline(vertices: [HatchPolylineVertex], isClosed: Bool, hasBulges: Bool)
    /// A chain of edges.
    case edges([HatchEdge])
}

/// One boundary path of a hatch.
struct HatchBoundaryPath {
    /// The path flags (DXF 92): 1 external, 2 polyline, 4 derived, 8 text box, 16 outermost.
    var flags = 0
    var shape: HatchBoundaryShape = .edges([])
    /// The handles of the objects the path was made from (DXF 330 after 97).
    var sourceBoundaries: [UInt64] = []

    var isPolyline: Bool { flags & 2 != 0 }
    var isDerived: Bool { flags & 4 != 0 }
}

/// One line of a hatch pattern's definition.
struct HatchPatternLine {
    /// The angle of the line, in radians (DXF 53).
    var angle = 0.0
    /// A point the line passes through (DXF 43, 44).
    var basePoint = DXF.Point2(0, 0)
    /// The offset to the next line (DXF 45, 46).
    var offset = DXF.Point2(0, 0)
    /// The lengths of the dashes, a gap when negative and a dot when 0 (DXF 49).
    var dashLengths: [Double] = []
}

/// The fields of a hatch entity, in the file's own terms: angles in radians, points in the
/// entity's own coordinate system.
struct HatchData {
    /// The gradient fill, which R2004 and later keep for every hatch, or `nil` before.
    var gradient: HatchGradient?
    /// The z coordinate of the hatch's plane (DXF 30).
    var elevation = 0.0
    /// The extrusion (DXF 210).
    var extrusion = DXF.Point(0, 0, 1)
    /// The name of the pattern (DXF 2).
    var patternName = ""
    /// Whether the hatch is a solid fill (DXF 70).
    var isSolid = false
    /// Whether the hatch follows the objects that bound it (DXF 71).
    var isAssociative = false
    var paths: [HatchBoundaryPath] = []
    /// How islands are treated (DXF 75): 0 odd parity, 1 outermost, 2 whole area.
    var style = 0
    /// 0 user defined, 1 predefined, 2 custom (DXF 76).
    var patternType = 0
    /// The angle of the pattern in radians (DXF 52), not kept for a solid fill.
    var patternAngle = 0.0
    /// The scale or the spacing of the pattern (DXF 41), not kept for a solid fill.
    var patternScale = 1.0
    /// Whether the pattern is drawn twice, the second time at right angles (DXF 77).
    var isDouble = false
    var patternLines: [HatchPatternLine] = []
    /// The pixel size, kept when a path is derived (DXF 47).
    var pixelSize: Double?
    var seedPoints: [DXF.Point2] = []
}

extension DXF.Point2 {
    fileprivate init(_ pair: (x: Double, y: Double)) {
        self.init(pair.x, pair.y)
    }
}

extension ObjectReader {
    /// Reads a hatch with its boundary paths, pattern, seed points and gradient.
    mutating func readHatch() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var hatch = HatchData()

        if version >= .ac1018 { hatch.gradient = try readHatchGradient() }

        hatch.elevation = try main.readBitDouble()
        let extrusion = try main.read3BitDouble()
        hatch.extrusion = DXF.Point(extrusion.x, extrusion.y, extrusion.z)
        hatch.patternName = try readText()
        hatch.isSolid = try main.readBit()
        hatch.isAssociative = try main.readBit()

        let pathCount = try DimensionsSupport.boundedCount(
            try main.readBitLong(), bitsEach: 6, in: self, what: "hatch paths")
        var hasDerivedBoundary = false
        for _ in 0..<pathCount {
            let path = try readHatchPath()
            if path.isDerived { hasDerivedBoundary = true }
            hatch.paths.append(path)
        }

        hatch.style = Int(try main.readBitShort())
        hatch.patternType = Int(try main.readBitShort())

        if !hatch.isSolid {
            hatch.patternAngle = try main.readBitDouble()
            hatch.patternScale = try main.readBitDouble()
            hatch.isDouble = try main.readBit()

            let lineCount = try DimensionsSupport.boundedCount(
                Int32(try main.readBitShort()), bitsEach: 12, in: self,
                what: "hatch pattern lines")
            for _ in 0..<lineCount {
                var line = HatchPatternLine()
                line.angle = try main.readBitDouble()
                line.basePoint = DXF.Point2(try main.read2BitDouble())
                line.offset = DXF.Point2(try main.read2BitDouble())
                let dashCount = try DimensionsSupport.boundedCount(
                    Int32(try main.readBitShort()), bitsEach: 2, in: self,
                    what: "hatch pattern dashes")
                for _ in 0..<dashCount { line.dashLengths.append(try main.readBitDouble()) }
                hatch.patternLines.append(line)
            }
        }

        if hasDerivedBoundary { hatch.pixelSize = try main.readBitDouble() }

        let seedCount = try DimensionsSupport.boundedCount(
            try main.readBitLong(), bitsEach: 128, in: self, what: "hatch seed points")
        for _ in 0..<seedCount {
            hatch.seedPoints.append(DXF.Point2(try main.read2RawDouble()))
        }
        return DecodedEntity(common: common, geometry: .hatch(hatch))
    }

    /// Reads the gradient fill that R2004 and later put before the rest of a hatch.
    private mutating func readHatchGradient() throws -> HatchGradient {
        var gradient = HatchGradient()
        gradient.isEnabled = try main.readBitLong() != 0
        gradient.reserved = Int(try main.readBitLong())
        gradient.angle = try main.readBitDouble()
        gradient.shift = try main.readBitDouble()
        gradient.isSingleColor = try main.readBitLong() != 0
        gradient.tint = try main.readBitDouble()

        let count = try DimensionsSupport.boundedCount(
            try main.readBitLong(), bitsEach: 14, in: self, what: "gradient colours")
        for _ in 0..<count {
            let position = try main.readBitDouble()
            gradient.colors.append(
                HatchGradientColor(position: position, color: try readGradientColor()))
        }
        gradient.name = try readText()
        return gradient
    }

    /// Reads a colour as R2004 and later keep it in a gradient: a colour index that is always 0,
    /// a long whose top byte says how the rest is a colour, and the names of a colour book.
    private mutating func readGradientColor() throws -> DWGColor {
        _ = try main.readBitShort()
        let word = UInt32(bitPattern: try main.readBitLong())
        let flags = try main.readByte()
        // Bit 0 says a colour name follows, bit 1 a colour book name.
        // (`readText` is also the name of the TEXT entity reader, so the type picks this one.)
        if flags & 1 != 0 { _ = try readText() as String }
        if flags & 2 != 0 { _ = try readText() as String }

        if word == 0xC000_0000 { return .byLayer }
        if word & 0x0100_0000 != 0 { return Self.indexColor(Int(word & 0xFF)) }
        return .rgb(
            red: UInt8(truncatingIfNeeded: word >> 16),
            green: UInt8(truncatingIfNeeded: word >> 8),
            blue: UInt8(truncatingIfNeeded: word))
    }

    /// Reads one boundary path.
    private mutating func readHatchPath() throws -> HatchBoundaryPath {
        var path = HatchBoundaryPath()
        path.flags = Int(try main.readBitLong())

        if path.isPolyline {
            let hasBulges = try main.readBit()
            let isClosed = try main.readBit()
            let count = try DimensionsSupport.boundedCount(
                try main.readBitLong(), bitsEach: 128, in: self, what: "hatch polyline vertices")
            var vertices: [HatchPolylineVertex] = []
            for _ in 0..<count {
                let point = DXF.Point2(try main.read2RawDouble())
                let bulge = try hasBulges ? main.readBitDouble() : 0
                vertices.append(HatchPolylineVertex(point: point, bulge: bulge))
            }
            path.shape = .polyline(vertices: vertices, isClosed: isClosed, hasBulges: hasBulges)
        } else {
            let count = try DimensionsSupport.boundedCount(
                try main.readBitLong(), bitsEach: 16, in: self, what: "hatch edges")
            var edges: [HatchEdge] = []
            for _ in 0..<count { edges.append(try readHatchEdge()) }
            path.shape = .edges(edges)
        }

        let handleCount = try DimensionsSupport.boundedCount(
            try main.readBitLong(), bitsEach: 8, stream: .handles, in: self,
            what: "hatch boundary handles")
        for _ in 0..<handleCount { path.sourceBoundaries.append(try readOwnHandle()) }
        return path
    }

    /// Reads one edge of an edge path.
    private mutating func readHatchEdge() throws -> HatchEdge {
        switch try main.readByte() {
        case 1:
            let start = DXF.Point2(try main.read2RawDouble())
            let end = DXF.Point2(try main.read2RawDouble())
            return .line(start: start, end: end)
        case 2:
            let center = DXF.Point2(try main.read2RawDouble())
            let radius = try main.readBitDouble()
            let start = try main.readBitDouble()
            let end = try main.readBitDouble()
            return .circularArc(
                center: center, radius: radius, startAngle: start, endAngle: end,
                counterClockwise: try main.readBit())
        case 3:
            let center = DXF.Point2(try main.read2RawDouble())
            let axis = DXF.Point2(try main.read2RawDouble())
            let ratio = try main.readBitDouble()
            let start = try main.readBitDouble()
            let end = try main.readBitDouble()
            return .ellipticArc(
                center: center, majorAxisEnd: axis, minorToMajorRatio: ratio, startAngle: start,
                endAngle: end, counterClockwise: try main.readBit())
        case 4:
            return .spline(try readHatchSplineEdge())
        case let other:
            throw DWG.Error.invalid("hatch edge type \(other)")
        }
    }

    private mutating func readHatchSplineEdge() throws -> HatchSplineEdge {
        var spline = HatchSplineEdge()
        spline.degree = Int(try main.readBitLong())
        spline.isRational = try main.readBit()
        spline.isPeriodic = try main.readBit()

        let knotCount = try DimensionsSupport.boundedCount(
            try main.readBitLong(), bitsEach: 2, in: self, what: "hatch spline knots")
        let pointCount = try DimensionsSupport.boundedCount(
            try main.readBitLong(), bitsEach: 128, in: self, what: "hatch spline control points")
        for _ in 0..<knotCount { spline.knots.append(try main.readBitDouble()) }
        for _ in 0..<pointCount {
            spline.controlPoints.append(DXF.Point2(try main.read2RawDouble()))
            if spline.isRational { spline.weights.append(try main.readBitDouble()) }
        }

        if version >= .ac1024 {
            let fitCount = try DimensionsSupport.boundedCount(
                try main.readBitLong(), bitsEach: 128, in: self, what: "hatch spline fit points")
            if fitCount > 0 {
                for _ in 0..<fitCount {
                    spline.fitPoints.append(DXF.Point2(try main.read2RawDouble()))
                }
                spline.startTangent = DXF.Point2(try main.read2RawDouble())
                spline.endTangent = DXF.Point2(try main.read2RawDouble())
            }
        }
        return spline
    }
}
