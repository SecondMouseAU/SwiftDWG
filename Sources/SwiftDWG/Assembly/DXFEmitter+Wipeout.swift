import SwiftDXF

extension DXFEmitter {
    /// Writes a wipeout with the groups AutoCAD's DXF uses for it, in its order.
    ///
    /// A polygonal clip boundary is written closed, with its first vertex repeated at the end and
    /// counted, as AutoCAD does. The image definition (340) and its reactor (360) are written even
    /// when they are 0, which they are for a wipeout.
    mutating func writeWipeout(_ wipeout: WipeoutData, common: EntityCommon, space: Space) {
        writer.begin("WIPEOUT")
        writeCommon(common, space: space)
        writer.group(90, wipeout.classVersion)
        writer.point(10, wipeout.insertion)
        writer.point(11, wipeout.uVector)
        writer.point(12, wipeout.vVector)
        writer.point2D(13, x: wipeout.size.x, y: wipeout.size.y)
        writer.handle(340, wipeout.imageDefinition)
        writer.group(70, wipeout.displayFlags)
        writer.group(280, wipeout.isClipping ? 1 : 0)
        writer.group(281, wipeout.brightness)
        writer.group(282, wipeout.contrast)
        writer.group(283, wipeout.fade)
        if let inside = wipeout.clipsInside { writer.group(290, inside ? 1 : 0) }
        writer.handle(360, wipeout.imageReactor)
        writer.group(71, wipeout.clipType)
        var vertices = wipeout.clipVertices
        if wipeout.clipType == 2, let first = vertices.first { vertices.append(first) }
        writer.group(91, vertices.count)
        for vertex in vertices { writer.point2D(14, x: vertex.x, y: vertex.y) }
    }
}
