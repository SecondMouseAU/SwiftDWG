import SwiftDXF

extension DXFEmitter {
    /// Writes a tolerance with the groups AutoCAD's DXF uses for it, in its order.
    ///
    /// AutoCAD leaves the direction (11) and the extrusion (210) out when they are the usual
    /// (1, 0, 0) and (0, 0, 1).
    mutating func writeTolerance(
        _ tolerance: ToleranceData, common: EntityCommon, space: Space
    ) {
        writer.begin("TOLERANCE")
        writeCommon(common, space: space)
        if let style = document.dimensionStyleNames[tolerance.style] { writer.group(3, style) }
        writer.point(10, tolerance.insertion)
        writer.group(1, tolerance.text)
        writeExtrusion(tolerance.extrusion)
        if tolerance.direction != DXF.Point(1, 0, 0) { writer.point(11, tolerance.direction) }
    }
}
