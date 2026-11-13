// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readEllipse, readSpline). See NOTICE.md. The field order is the format's own, from the Open
// Design Specification for .dwg files.

import SwiftDXF

/// An ellipse or an elliptical arc.
///
/// The centre and the major axis are in the world coordinate system, as the file keeps them.
struct EllipseData {
    var center: DXF.Point
    /// The vector from the centre to the end of the semi-major axis.
    var majorAxis: DXF.Point
    var extrusion: DXF.Point
    /// The minor radius over the major radius, as stored (not limited to 0...1).
    var ratio: Double
    /// Where the arc starts on the ellipse, as the eccentric anomaly in radians.
    var startParameter: Double
    /// Where the arc ends, in radians.
    var endParameter: Double
}

/// A spline: a B-spline made from control points and knots, or from points it is fitted through.
///
/// A file holds one of two forms, which the stored scenario number tells apart: the control points
/// and knots, or only the fit points. R2013 and later keep extra method flags and a knot
/// parameterisation, from which the scenario is worked out.
struct SplineData {
    /// 1 when the control points and knots are stored, 2 when only the fit points are.
    var scenario = 1
    /// The method flags, which R2013 and later store.
    ///
    /// They are 1 for fit points, 2 for the control frame shown, 4 for closed and 8 for the knot
    /// parameterisation in use. Before R2013 this is 1 when the scenario is 2, and else 0.
    var methodFlags = 0
    /// How the knots were made: 0 chord, 1 square root, 2 uniform, 15 custom.
    var knotParameter = 0
    var degree = 0
    /// Whether weights are in use: the rational flag of the control-point form.
    var isRational = false
    /// The closed flag of the control-point form.
    var isClosedFlag = false
    /// The periodic flag of the control-point form.
    var isPeriodic = false
    var knotTolerance = 0.0
    var controlPointTolerance = 0.0
    var fitTolerance = 0.0
    /// The tangent at the first fit point, of the fit-point form.
    var startTangent = DXF.Point(0, 0, 0)
    /// The tangent at the last fit point, of the fit-point form.
    var endTangent = DXF.Point(0, 0, 0)
    var knots: [Double] = []
    var controlPoints: [DXF.Point] = []
    /// One weight per control point when the file has them, else empty.
    var weights: [Double] = []
    var fitPoints: [DXF.Point] = []

    /// Whether the spline closes on itself, by either of the two places the file can say so.
    var isClosed: Bool { isClosedFlag || methodFlags & 4 != 0 }
}

extension ObjectReader {
    mutating func readEllipse() throws -> DecodedEntity {
        let common = try readEntityCommon()
        let center = DXF.Point(fromBits: try main.read3BitDouble())
        let majorAxis = DXF.Point(fromBits: try main.read3BitDouble())
        // The extrusion is a plain 3BD here in every release, not the one-bit form.
        let extrusion = DXF.Point(fromBits: try main.read3BitDouble())
        let ratio = try main.readBitDouble()
        let start = try main.readBitDouble()
        let end = try main.readBitDouble()
        return DecodedEntity(
            common: common,
            geometry: .ellipse(
                EllipseData(
                    center: center, majorAxis: majorAxis, extrusion: extrusion, ratio: ratio,
                    startParameter: start, endParameter: end)))
    }

    mutating func readSpline() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var spline = SplineData()
        var scenario = Int(try main.readBitLong())

        if version >= .ac1027 {
            // R2013 and later: the scenario above is not used. Flags and a knot parameter come
            // next, and the scenario is 1 for custom knots or when the knot parameter is not in
            // use, and else 2.
            spline.methodFlags = Int(try main.readBitLong())
            spline.knotParameter = Int(try main.readBitLong())
            scenario = (spline.knotParameter == 15 || spline.methodFlags & 8 == 0) ? 1 : 2
        } else if scenario == 2 {
            spline.methodFlags = 1
        } else {
            // Without fit data the knots are the file's own.
            spline.knotParameter = 15
        }
        guard scenario == 1 || scenario == 2 else {
            throw DWG.Error.invalid("spline scenario \(scenario)")
        }
        spline.scenario = scenario
        spline.degree = Int(try main.readBitLong())

        var knotCount = 0
        var controlCount = 0
        var fitCount = 0
        var hasWeights = false
        if scenario == 1 {
            spline.isRational = try main.readBit()
            spline.isClosedFlag = try main.readBit()
            spline.isPeriodic = try main.readBit()
            spline.knotTolerance = try main.readBitDouble()
            spline.controlPointTolerance = try main.readBitDouble()
            // Both counts are stored as long values, though DXF writes them as shorts.
            let knots = try main.readBitLong()
            let controls = try main.readBitLong()
            hasWeights = try main.readBit()
            knotCount = try checkedElementCount(knots, bitsEach: 2, "spline knots")
            controlCount = try checkedElementCount(
                controls, bitsEach: hasWeights ? 8 : 6, "spline control points")
        } else {
            spline.fitTolerance = try main.readBitDouble()
            spline.startTangent = DXF.Point(fromBits: try main.read3BitDouble())
            spline.endTangent = DXF.Point(fromBits: try main.read3BitDouble())
            fitCount = try checkedElementCount(
                try main.readBitLong(), bitsEach: 6, "spline fit points")
        }

        for _ in 0..<knotCount { spline.knots.append(try main.readBitDouble()) }
        for _ in 0..<controlCount {
            spline.controlPoints.append(DXF.Point(fromBits: try main.read3BitDouble()))
            if hasWeights { spline.weights.append(try main.readBitDouble()) }
        }
        for _ in 0..<fitCount {
            spline.fitPoints.append(DXF.Point(fromBits: try main.read3BitDouble()))
        }
        return DecodedEntity(common: common, geometry: .spline(spline))
    }
}
