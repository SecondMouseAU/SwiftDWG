// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readLWPolyline, readPolyline2D, readPolyline3D, readVertex2D, readVertex3D, readSeqend). See
// NOTICE.md. The field order is the format's own, from the Open Design Specification for .dwg
// files.

import SwiftDXF

/// A lightweight polyline: a flat run of points with optional bulges and widths.
///
/// The points are in the entity's own coordinate system, at the elevation given.
struct LWPolylineData {
    /// The start and end width of the segment that begins at a point.
    struct Width: Equatable {
        var start: Double
        var end: Double
    }

    /// The flags word as stored: 1 the extrusion is given, 2 the thickness, 4 a constant width,
    /// 8 the elevation, 0x10 bulges, 0x20 widths, 0x100 line type generation across the whole
    /// polyline, 0x200 closed, 0x400 vertex ids.
    var flags = 0
    var constantWidth = 0.0
    var elevation = 0.0
    var thickness = 0.0
    var extrusion = DXF.Point(0, 0, 1)
    var points: [DXF.Point2] = []
    /// The bulge of the segment that begins at each point, when the file has them, else empty.
    var bulges: [Double] = []
    /// The id of each point, when the file has them (R2010 and later), else empty.
    var vertexIDs: [Int] = []
    /// The widths of the segment that begins at each point, when the file has them, else empty.
    var widths: [Width] = []

    var isClosed: Bool { flags & 0x200 != 0 }
    var hasLineTypeGeneration: Bool { flags & 0x100 != 0 }
}

/// A 2D polyline: the header of a run of `VERTEX` entities that ends with a `SEQEND`.
///
/// The vertices are separate entities. From R2004 the file lists their handles; before that it
/// names the first and the last, and the ones between are the entities that follow in the chain.
struct Polyline2DData {
    /// The flags as DXF has them in group 70: 1 closed, 2 curve fit, 4 spline fit, 0x80 line type
    /// generation.
    var flags = 0
    /// The curve and smooth surface type, as DXF has it in group 75.
    var curveType = 0
    /// The width a vertex has when it gives none of its own.
    var defaultStartWidth = 0.0
    var defaultEndWidth = 0.0
    var thickness = 0.0
    /// The z of every vertex, which a 2D vertex does not carry itself.
    var elevation = 0.0
    var extrusion = DXF.Point(0, 0, 1)
    /// The handles of the vertices in order (R2004 and later), else empty.
    var vertexHandles: [UInt64] = []
    /// The handle of the first vertex (before R2004), else 0.
    var firstVertex: UInt64 = 0
    /// The handle of the last vertex (before R2004), else 0.
    var lastVertex: UInt64 = 0
    /// The handle of the `SEQEND` that closes the run of vertices.
    var seqend: UInt64 = 0

    var isClosed: Bool { flags & 1 != 0 }
}

/// A 3D polyline: the header of a run of `VERTEX` entities that ends with a `SEQEND`.
///
/// The file keeps two bytes of flags, and DXF's groups 70 and 75 are worked out from them.
struct Polyline3DData {
    /// The first flags byte as stored: bit 0 for a quadratic spline fit, bit 1 for a cubic one.
    var curveBits: UInt8 = 0
    /// The second flags byte as stored: bit 0 for closed.
    var closedBits: UInt8 = 0
    /// The handles of the vertices in order (R2004 and later), else empty.
    var vertexHandles: [UInt64] = []
    /// The handle of the first vertex (before R2004), else 0.
    var firstVertex: UInt64 = 0
    /// The handle of the last vertex (before R2004), else 0.
    var lastVertex: UInt64 = 0
    /// The handle of the `SEQEND` that closes the run of vertices.
    var seqend: UInt64 = 0

    var isClosed: Bool { closedBits & 1 != 0 }
    /// The smooth curve type as DXF has it in group 75: 0 none, 5 quadratic, 6 cubic.
    var curveType: Int {
        if curveBits & 1 != 0 { return 5 }
        if curveBits & 2 != 0 { return 6 }
        return 0
    }
    /// The flags as DXF has them in group 70: 1 closed, 4 spline fit, 8 for a 3D polyline.
    var flags: Int {
        var value = 8
        if isClosed { value |= 1 }
        if curveBits & 3 != 0 { value |= 4 }
        return value
    }
}

/// A vertex of a 2D polyline.
struct Vertex2DData {
    /// The flags as stored, as DXF has them in group 70.
    var flags = 0
    /// Where the vertex is.
    ///
    /// The z is 0 in a file, and the polyline's elevation applies.
    var location = DXF.Point(0, 0, 0)
    /// The width of the segment that starts here.
    ///
    /// A file that stores a negative start width means that value without the sign for both
    /// widths, and this holds that resolved.
    var startWidth = 0.0
    var endWidth = 0.0
    var bulge = 0.0
    /// The vertex id (R2010 and later), else 0.
    var id = 0
    /// The tangent direction for a curve-fit polyline, in radians.
    var curveTangent = 0.0
}

/// A vertex of a 3D polyline.
struct Vertex3DData {
    /// The flags as stored, as DXF has them in group 70.
    var flags = 0
    var location = DXF.Point(0, 0, 0)
}

extension ObjectReader {
    mutating func readLWPolyline() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var polyline = LWPolylineData()

        // The data of the entity starts at its flags word, and each flag says that a value
        // follows, or, for the arrays, that a count does.
        let flags = try readFlagsWord()
        polyline.flags = flags
        if flags & 4 != 0 { polyline.constantWidth = try main.readBitDouble() }
        if flags & 8 != 0 { polyline.elevation = try main.readBitDouble() }
        if flags & 2 != 0 { polyline.thickness = try main.readBitDouble() }
        if flags & 1 != 0 { polyline.extrusion = DXF.Point(fromBits: try main.read3BitDouble()) }

        let pointCount = try main.readBitLong()
        let bulgeCount = try flags & 0x10 != 0 ? main.readBitLong() : 0
        let idCount = try flags & 0x400 != 0 ? main.readBitLong() : 0
        let widthCount = try flags & 0x20 != 0 ? main.readBitLong() : 0

        // R13 and R14 write every point in full. Later releases write the first in full, and each
        // of the others against the point before it, so a coordinate that repeats takes few bits.
        let points = try checkedElementCount(
            pointCount, bitsEach: version <= .ac1014 ? 128 : 4, "polyline points")
        let bulges = try checkedElementCount(bulgeCount, bitsEach: 2, "polyline bulges")
        let ids = try checkedElementCount(idCount, bitsEach: 2, "polyline vertex ids")
        let widths = try checkedElementCount(widthCount, bitsEach: 4, "polyline widths")
        guard bulges <= points, ids <= points, widths <= points else {
            throw DWG.Error.invalid("a polyline with \(points) points and more of bulges or widths")
        }

        if version <= .ac1014 {
            for _ in 0..<points {
                let location = try main.read2RawDouble()
                polyline.points.append(DXF.Point2(location.x, location.y))
            }
        } else if points > 0 {
            var location = try main.read2RawDouble()
            polyline.points.append(DXF.Point2(location.x, location.y))
            for _ in 1..<points {
                location = try main.read2BitDouble(default: location)
                polyline.points.append(DXF.Point2(location.x, location.y))
            }
        }
        for _ in 0..<bulges { polyline.bulges.append(try main.readBitDouble()) }
        for _ in 0..<ids { polyline.vertexIDs.append(Int(try main.readBitLong())) }
        for _ in 0..<widths {
            let start = try main.readBitDouble()
            let end = try main.readBitDouble()
            polyline.widths.append(LWPolylineData.Width(start: start, end: end))
        }
        return DecodedEntity(common: common, geometry: .lwpolyline(polyline))
    }

    /// Reads what both kinds of polyline end with: the vertices it owns, and its `SEQEND`.
    ///
    /// R2004 and later count the vertices in the data and list their handles. Before that the
    /// first and the last vertex are named. ACadSharp reads these handles against a reference of
    /// 0; they are read against the polyline's own handle here, which is the same for the
    /// absolute forms and right for the relative ones.
    private mutating func readVertexHandles() throws -> (
        list: [UInt64], first: UInt64, last: UInt64, seqend: UInt64
    ) {
        var list: [UInt64] = []
        var first: UInt64 = 0
        var last: UInt64 = 0
        if version >= .ac1018 {
            let count = try checkedHandleCount(try main.readBitLong(), "owned vertices")
            for _ in 0..<count { list.append(try readOwnHandle()) }
        } else {
            first = try readOwnHandle()
            last = try readOwnHandle()
        }
        let seqend = try readOwnHandle()
        return (list, first, last, seqend)
    }

    mutating func readPolyline2D() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var polyline = Polyline2DData()
        polyline.flags = try readFlagsWord()
        polyline.curveType = try readFlagsWord()
        polyline.defaultStartWidth = try main.readBitDouble()
        polyline.defaultEndWidth = try main.readBitDouble()
        polyline.thickness = try main.readBitThickness()
        polyline.elevation = try main.readBitDouble()
        polyline.extrusion = DXF.Point(fromBits: try main.readBitExtrusion())
        let owned = try readVertexHandles()
        polyline.vertexHandles = owned.list
        polyline.firstVertex = owned.first
        polyline.lastVertex = owned.last
        polyline.seqend = owned.seqend
        return DecodedEntity(common: common, geometry: .polyline2D(polyline))
    }

    mutating func readPolyline3D() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var polyline = Polyline3DData()
        polyline.curveBits = try main.readByte()
        polyline.closedBits = try main.readByte()
        let owned = try readVertexHandles()
        polyline.vertexHandles = owned.list
        polyline.firstVertex = owned.first
        polyline.lastVertex = owned.last
        polyline.seqend = owned.seqend
        return DecodedEntity(common: common, geometry: .polyline3D(polyline))
    }

    mutating func readVertex2D() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var vertex = Vertex2DData()
        vertex.flags = Int(try main.readByte())
        vertex.location = DXF.Point(fromBits: try main.read3BitDouble())
        // A negative start width is a short form: it is both widths, and no end width follows.
        let width = try main.readBitDouble()
        if width < 0 {
            vertex.startWidth = -width
            vertex.endWidth = -width
        } else {
            vertex.startWidth = width
            vertex.endWidth = try main.readBitDouble()
        }
        vertex.bulge = try main.readBitDouble()
        if version >= .ac1024 { vertex.id = Int(try main.readBitLong()) }
        vertex.curveTangent = try main.readBitDouble()
        return DecodedEntity(common: common, geometry: .vertex2D(vertex))
    }

    mutating func readVertex3D() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var vertex = Vertex3DData()
        vertex.flags = Int(try main.readByte())
        vertex.location = DXF.Point(fromBits: try main.read3BitDouble())
        return DecodedEntity(common: common, geometry: .vertex3D(vertex))
    }

    mutating func readSeqend() throws -> DecodedEntity {
        DecodedEntity(common: try readEntityCommon(), geometry: .seqend)
    }
}
