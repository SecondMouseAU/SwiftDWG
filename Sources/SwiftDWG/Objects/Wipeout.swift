// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readCadImage, which reads WIPEOUT and the IMAGE entity alike). See NOTICE.md. The field order
// is the format's own, from the Open Design Specification for .dwg files.

import SwiftDXF

extension ObjectType {
    /// The code a WIPEOUT is read as.
    ///
    /// A WIPEOUT has no fixed code: the file defines a class for it and its objects carry that
    /// class's number, which `fixedCode(of:classes:)` turns into this. No file holds this value
    /// as a type, since a code is read as 16 bits at most.
    static let wipeout = 0x10001
}

/// The fields of a WIPEOUT entity: a masking area, which the file keeps as an image with no
/// picture whose clip boundary is the area.
///
/// Points and vectors are in the world coordinate system. The clip vertices are in pixels of the
/// image, measured as the DXF does.
struct WipeoutData: Equatable {
    /// The class version (DXF 90), 0 in every file seen.
    var classVersion = 0
    /// The corner of the image the vectors start from (DXF 10, 20, 30).
    var insertion = DXF.Point(0, 0, 0)
    /// The vector along the bottom of the image that one pixel takes (DXF 11, 21, 31).
    var uVector = DXF.Point(1, 0, 0)
    /// The vector along the left side of the image that one pixel takes (DXF 12, 22, 32).
    var vVector = DXF.Point(0, 1, 0)
    /// The size of the image in pixels (DXF 13, 23).
    var size = DXF.Point2(1, 1)
    /// The display flags (DXF 70): 1 shows the image, 2 shows it when not aligned with the screen,
    /// 4 is on while clipping, 8 for a transparent background.
    var displayFlags = 0
    /// Whether the clip boundary is on (DXF 280).
    var isClipping = false
    /// The brightness (DXF 281), 50 by default.
    var brightness = 50
    /// The contrast (DXF 282), 50 by default.
    var contrast = 50
    /// The fade (DXF 283), 0 by default.
    var fade = 0
    /// Whether the area inside the boundary is kept and not the area outside it (DXF 290), kept
    /// from R2010. `nil` before that, where the area inside is the one kept.
    var clipsInside: Bool?
    /// The kind of clip boundary (DXF 71): 1 for a rectangle given by two opposite corners, 2 for
    /// a polygon.
    var clipType = 1
    /// The vertices of the clip boundary in pixels (DXF 14, 24): two for a rectangle, and for a
    /// polygon as many as the file lists, without the first vertex repeated at the end.
    var clipVertices: [DXF.Point2] = []
    /// The handle of the image definition (DXF 340), 0 for a WIPEOUT, which has none.
    var imageDefinition: UInt64 = 0
    /// The handle of the image definition reactor (DXF 360), 0 for a WIPEOUT.
    var imageReactor: UInt64 = 0
}

extension ObjectReader {
    /// Reads a wipeout.
    mutating func readWipeout() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var wipeout = WipeoutData()

        wipeout.classVersion = Int(try main.readBitLong())
        wipeout.insertion = DXF.Point(fromBits: try main.read3BitDouble())
        wipeout.uVector = DXF.Point(fromBits: try main.read3BitDouble())
        wipeout.vVector = DXF.Point(fromBits: try main.read3BitDouble())
        let size = try main.read2RawDouble()
        wipeout.size = DXF.Point2(size.x, size.y)

        wipeout.displayFlags = Int(try main.readBitShort())
        wipeout.isClipping = try main.readBit()
        wipeout.brightness = Int(try main.readByte())
        wipeout.contrast = Int(try main.readByte())
        wipeout.fade = Int(try main.readByte())
        if version >= .ac1024 { wipeout.clipsInside = try main.readBit() }

        wipeout.clipType = Int(try main.readBitShort())
        switch wipeout.clipType {
        case 1:
            for _ in 0..<2 { wipeout.clipVertices.append(try readClipVertex()) }
        case 2:
            let count = try checkedElementCount(
                try main.readBitLong(), bitsEach: 128, "clip vertices")
            for _ in 0..<count { wipeout.clipVertices.append(try readClipVertex()) }
        default:
            break
        }

        wipeout.imageDefinition = try readOwnHandle()
        wipeout.imageReactor = try readOwnHandle()
        return DecodedEntity(common: common, geometry: .wipeout(wipeout))
    }

    private mutating func readClipVertex() throws -> DXF.Point2 {
        let vertex = try main.read2RawDouble()
        return DXF.Point2(vertex.x, vertex.y)
    }
}
