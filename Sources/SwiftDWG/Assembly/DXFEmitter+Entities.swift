import Foundation
import SwiftDXF

extension DXFEmitter {
    /// Writes one decoded entity, with the group codes AutoCAD's DXF uses for its type.
    mutating func write(_ entity: DecodedEntity, space: Space) {
        let common = entity.common
        switch entity.geometry {
        case .line(let start, let end, let thickness, let extrusion):
            writer.begin("LINE")
            writeCommon(common, space: space)
            writeThickness(thickness)
            writer.point(10, start)
            writer.point(11, end)
            writeExtrusion(extrusion)
        case .circle(let center, let radius, let thickness, let extrusion):
            writer.begin("CIRCLE")
            writeCommon(common, space: space)
            writeThickness(thickness)
            writer.point(10, center)
            writer.group(40, radius)
            writeExtrusion(extrusion)
        case .arc(let center, let radius, let thickness, let extrusion, let start, let end):
            writer.begin("ARC")
            writeCommon(common, space: space)
            writeThickness(thickness)
            writer.point(10, center)
            writer.group(40, radius)
            writer.group(50, Self.degrees(start))
            writer.group(51, Self.degrees(end))
            writeExtrusion(extrusion)
        case .point(let location, let thickness, let extrusion, let rotation):
            writer.begin("POINT")
            writeCommon(common, space: space)
            writeThickness(thickness)
            writer.point(10, location)
            writeExtrusion(extrusion)
            if rotation != 0 { writer.group(50, Self.degrees(rotation)) }
        case .text(let text):
            writeText(text, common: common, space: space)
        case .mtext(let text):
            writeMText(text, common: common, space: space)
        case .insert(let insert):
            writeInsert(insert, common: common, space: space)
        case .ellipse(let ellipse):
            writer.begin("ELLIPSE")
            writeCommon(common, space: space)
            writer.point(10, ellipse.center)
            writer.point(11, ellipse.majorAxis)
            writeExtrusion(ellipse.extrusion)
            writer.group(40, ellipse.ratio)
            writer.group(41, ellipse.startParameter)
            writer.group(42, ellipse.endParameter)
        case .spline(let spline):
            writeSpline(spline, common: common, space: space)
        case .lwpolyline(let polyline):
            writeLWPolyline(polyline, common: common, space: space)
        case .polyline2D(let polyline):
            writePolyline2D(polyline, common: common, space: space)
        case .polyline3D(let polyline):
            writePolyline3D(polyline, common: common, space: space)
        case .solid(let solid):
            writer.begin(solid.isTrace ? "TRACE" : "SOLID")
            writeCommon(common, space: space)
            writeThickness(solid.thickness)
            for (index, corner) in solid.corners.enumerated() { writer.point(10 + index, corner) }
            writeExtrusion(solid.extrusion)
        case .face3D(let face):
            writer.begin("3DFACE")
            writeCommon(common, space: space)
            for (index, corner) in face.corners.enumerated() { writer.point(10 + index, corner) }
            if face.invisibleEdges != 0 { writer.group(70, face.invisibleEdges) }
        case .dimension(let dimension):
            writeDimension(dimension, common: common, space: space)
        case .leader(let leader):
            writeLeader(leader, common: common, space: space)
        case .hatch(let hatch):
            writeHatch(hatch, common: common, space: space)
        case .vertex2D, .vertex3D, .seqend, .block, .endBlock:
            // Written with the polyline or block that owns them.
            return
        }
        switch entity.geometry {
        case .polyline2D, .polyline3D: break  // their extended data follows their own record
        default: writeExtendedData(common)
        }
    }

    /// The extended data of an entity, as the groups that follow its record.
    mutating func writeExtendedData(_ common: EntityCommon) {
        for record in common.extendedData {
            let name = document.applicationName(record.application)
            let groups = ExtendedDataDecoder.groups(
                record.bytes, version: document.version, textEncoding: store.textEncoding)
            guard let name else { continue }
            writer.group(1001, name)
            for group in groups {
                switch group.value {
                case .string(let value) where group.code >= 1010 && group.code <= 1013:
                    // A point: the three coordinates and their group codes in one value.
                    let parts = value.components(separatedBy: "\n")
                    if parts.count == 5, let x = Double(parts[0]), let y = Double(parts[2]),
                        let z = Double(parts[4])
                    {
                        writer.group(group.code, x)
                        writer.group(group.code + 10, y)
                        writer.group(group.code + 20, z)
                    }
                case .string(let value): writer.group(group.code, value)
                case .integer(let value): writer.group(group.code, value)
                case .real(let value): writer.group(group.code, value)
                }
            }
        }
    }

    // MARK: Text and inserts

    private mutating func writeText(_ text: TextData, common: EntityCommon, space: Space) {
        writer.begin("TEXT")
        writeCommon(common, space: space)
        writeThickness(text.thickness)
        writer.point(10, text.insertion)
        writer.group(40, text.height)
        writer.group(1, text.value)
        if text.rotation != 0 { writer.group(50, Self.degrees(text.rotation)) }
        if text.widthFactor != 1.0 { writer.group(41, text.widthFactor) }
        if text.obliqueAngle != 0 { writer.group(51, Self.degrees(text.obliqueAngle)) }
        if let style = document.textStyleNames[text.style] { writer.group(7, style) }
        if text.generation != 0 { writer.group(71, text.generation) }
        if text.horizontalAlignment != 0 { writer.group(72, text.horizontalAlignment) }
        if let alignment = text.alignmentPoint { writer.point(11, alignment) }
        writeExtrusion(text.extrusion)
        if text.verticalAlignment != 0 { writer.group(73, text.verticalAlignment) }
    }

    private mutating func writeMText(_ text: MTextData, common: EntityCommon, space: Space) {
        writer.begin("MTEXT")
        writeCommon(common, space: space)
        writer.point(10, text.insertion)
        writer.group(40, text.height)
        if text.rectangleWidth > 0 { writer.group(41, text.rectangleWidth) }
        writer.group(71, text.attachment)
        writer.group(72, text.drawingDirection)
        // The text is written in chunks of at most 250 characters: the last in group 1, the others
        // in group 3.
        var rest = Substring(text.value)
        while rest.count > 250 {
            writer.group(3, String(rest.prefix(250)))
            rest = rest.dropFirst(250)
        }
        writer.group(1, String(rest))
        if let style = document.textStyleNames[text.style] { writer.group(7, style) }
        writeExtrusion(text.extrusion)
        writer.point(11, text.xAxisDirection)
        writer.group(73, text.lineSpacingStyle)
        writer.group(44, text.lineSpacingFactor)
    }

    private mutating func writeInsert(_ insert: InsertData, common: EntityCommon, space: Space) {
        writer.begin("INSERT")
        writeCommon(common, space: space)
        writer.group(2, document.blockNames[insert.blockHeader] ?? "")
        writer.point(10, insert.insertion)
        if insert.xScale != 1 { writer.group(41, insert.xScale) }
        if insert.yScale != 1 { writer.group(42, insert.yScale) }
        if insert.zScale != 1 { writer.group(43, insert.zScale) }
        if insert.rotation != 0 { writer.group(50, Self.degrees(insert.rotation)) }
        if let grid = insert.grid {
            writer.group(70, grid.columnCount)
            writer.group(71, grid.rowCount)
            writer.group(44, grid.columnSpacing)
            writer.group(45, grid.rowSpacing)
        }
        writeExtrusion(insert.extrusion)
    }

    // MARK: Curves

    private mutating func writeSpline(_ spline: SplineData, common: EntityCommon, space: Space) {
        writer.begin("SPLINE")
        writeCommon(common, space: space)
        var flags = 8
        if spline.isClosed { flags |= 1 }
        if spline.isPeriodic { flags |= 2 }
        if spline.isRational { flags |= 4 }
        writer.group(70, flags)
        writer.group(71, spline.degree)
        writer.group(72, spline.knots.count)
        writer.group(73, spline.controlPoints.count)
        writer.group(74, spline.fitPoints.count)
        for knot in spline.knots { writer.group(40, knot) }
        for weight in spline.weights { writer.group(41, weight) }
        for point in spline.controlPoints { writer.point(10, point) }
        for point in spline.fitPoints { writer.point(11, point) }
    }

    private mutating func writeLWPolyline(
        _ polyline: LWPolylineData, common: EntityCommon, space: Space
    ) {
        writer.begin("LWPOLYLINE")
        writeCommon(common, space: space)
        writer.group(90, polyline.points.count)
        var flags = 0
        if polyline.isClosed { flags |= 1 }
        if polyline.hasLineTypeGeneration { flags |= 128 }
        writer.group(70, flags)
        if polyline.constantWidth != 0 { writer.group(43, polyline.constantWidth) }
        if polyline.elevation != 0 { writer.group(38, polyline.elevation) }
        writeThickness(polyline.thickness)
        for (index, point) in polyline.points.enumerated() {
            writer.point2D(10, x: point.x, y: point.y)
            if index < polyline.widths.count {
                writer.group(40, polyline.widths[index].start)
                writer.group(41, polyline.widths[index].end)
            }
            if index < polyline.bulges.count, polyline.bulges[index] != 0 {
                writer.group(42, polyline.bulges[index])
            }
            if index < polyline.vertexIDs.count { writer.group(91, polyline.vertexIDs[index]) }
        }
        writeExtrusion(polyline.extrusion)
    }

    private mutating func writePolyline2D(
        _ polyline: Polyline2DData, common: EntityCommon, space: Space
    ) {
        let found = vertices(
            owned: polyline.vertexHandles, first: polyline.firstVertex, last: polyline.lastVertex
        ) { geometry -> Vertex2DData? in
            if case .vertex2D(let data) = geometry { return data }
            return nil
        }
        // A polyline with a vertex missing is a different shape: it is counted, not written short.
        guard let found else {
            writeBare("UNREADABLE_POLYLINE", handle: common.handle, space: space)
            return
        }
        writer.begin("POLYLINE")
        writeCommon(common, space: space)
        writer.group(66, 1)
        writer.point(10, DXF.Point(0, 0, polyline.elevation))
        writeThickness(polyline.thickness)
        writer.group(70, polyline.flags)
        if polyline.defaultStartWidth != 0 { writer.group(40, polyline.defaultStartWidth) }
        if polyline.defaultEndWidth != 0 { writer.group(41, polyline.defaultEndWidth) }
        if polyline.curveType != 0 { writer.group(75, polyline.curveType) }
        writeExtrusion(polyline.extrusion)
        writeExtendedData(common)
        for (vertexCommon, data) in found {
            writer.begin("VERTEX")
            writeCommon(vertexCommon, space: space)
            writer.point(10, data.location)
            if data.startWidth != 0 { writer.group(40, data.startWidth) }
            if data.endWidth != 0 { writer.group(41, data.endWidth) }
            if data.bulge != 0 { writer.group(42, data.bulge) }
            writer.group(70, data.flags)
            if data.curveTangent != 0 { writer.group(50, Self.degrees(data.curveTangent)) }
            if data.id != 0 { writer.group(91, data.id) }
        }
        writeSequenceEnd(polyline.seqend, like: common, space: space)
    }

    private mutating func writePolyline3D(
        _ polyline: Polyline3DData, common: EntityCommon, space: Space
    ) {
        let found = vertices(
            owned: polyline.vertexHandles, first: polyline.firstVertex, last: polyline.lastVertex
        ) { geometry -> Vertex3DData? in
            if case .vertex3D(let data) = geometry { return data }
            return nil
        }
        guard let found else {
            writeBare("UNREADABLE_POLYLINE", handle: common.handle, space: space)
            return
        }
        writer.begin("POLYLINE")
        writeCommon(common, space: space)
        writer.group(66, 1)
        writer.point(10, DXF.Point(0, 0, 0))
        writer.group(70, polyline.flags)
        writeExtendedData(common)
        for (vertexCommon, data) in found {
            writer.begin("VERTEX")
            writeCommon(vertexCommon, space: space)
            writer.point(10, data.location)
            writer.group(70, data.flags)
        }
        writeSequenceEnd(polyline.seqend, like: common, space: space)
    }

    /// The vertices of a polyline, each read and picked out by `pick`, or `nil` if one cannot be
    /// read or is not the kind a vertex of this polyline is.
    private func vertices<Vertex>(
        owned: [UInt64], first: UInt64, last: UInt64, _ pick: (EntityGeometry) -> Vertex?
    ) -> [(common: EntityCommon, data: Vertex)]? {
        var out: [(common: EntityCommon, data: Vertex)] = []
        for handle in vertexHandles(owned: owned, first: first, last: last) {
            guard let vertex = try? store.entity(handle), let data = pick(vertex.geometry) else {
                return nil
            }
            out.append((vertex.common, data))
        }
        return out
    }

    /// The vertices of a polyline: listed from R2004, before that the first and the last with each
    /// one naming the next.
    private func vertexHandles(owned: [UInt64], first: UInt64, last: UInt64) -> [UInt64] {
        if !owned.isEmpty || document.version >= .ac1018 { return owned.filter { $0 != 0 } }
        guard first != 0 else { return [] }
        var out: [UInt64] = []
        var seen = Set<UInt64>()
        var handle = first
        while handle != 0, seen.insert(handle).inserted, out.count < 1 << 22 {
            out.append(handle)
            if handle == last { break }
            guard var reader = try? store.reader(for: handle),
                let vertex = try? reader.readEntityCommonForChain()
            else { break }
            handle = vertex.next != 0 ? vertex.next : handle + 1
        }
        return out
    }

    private mutating func writeSequenceEnd(
        _ handle: UInt64, like common: EntityCommon, space: Space
    ) {
        writer.begin("SEQEND")
        writer.handle(5, handle)
        if space == .paper { writer.group(67, 1) }
        writer.group(8, document.layerNames[common.layer] ?? "0")
    }

    // MARK: Dimensions and leaders

    private mutating func writeDimension(
        _ dimension: DimensionData, common: EntityCommon, space: Space
    ) {
        writer.begin("DIMENSION")
        writeCommon(common, space: space)
        writer.group(2, document.blockNames[dimension.block] ?? "")
        writer.point(10, dimension.definitionPoint)
        writer.point(11, dimension.textMidPoint)
        writer.group(70, dimension.typeFlags)
        if let attachment = dimension.attachmentPoint { writer.group(71, attachment) }
        if let style = dimension.lineSpacingStyle { writer.group(72, style) }
        if let factor = dimension.lineSpacingFactor { writer.group(41, factor) }
        if let measurement = dimension.measurement { writer.group(42, measurement) }
        if !dimension.text.isEmpty { writer.group(1, dimension.text) }
        if let style = document.dimensionStyleNames[dimension.style] { writer.group(3, style) }
        if dimension.textRotation != 0 { writer.group(53, Self.degrees(dimension.textRotation)) }
        if dimension.horizontalDirection != 0 {
            writer.group(51, Self.degrees(dimension.horizontalDirection))
        }
        writeExtrusion(dimension.extrusion)
        if dimension.insertionPoint != DXF.Point(0, 0, 0) {
            writer.point(12, dimension.insertionPoint)
        }
        if let point = dimension.firstPoint { writer.point(13, point) }
        if let point = dimension.secondPoint { writer.point(14, point) }
        if let point = dimension.vertexPoint { writer.point(15, point) }
        if let point = dimension.arcPoint { writer.point(16, point) }
        if let length = dimension.leaderLength { writer.group(40, length) }
        if let rotation = dimension.rotation, rotation != 0 {
            writer.group(50, Self.degrees(rotation))
        }
        if let oblique = dimension.extLineRotation, oblique != 0 {
            writer.group(52, Self.degrees(oblique))
        }
    }

    private mutating func writeLeader(_ leader: LeaderData, common: EntityCommon, space: Space) {
        writer.begin("LEADER")
        writeCommon(common, space: space)
        writer.group(3, document.dimensionStyleNames[leader.style] ?? "")
        writer.group(71, leader.hasArrowHead ? 1 : 0)
        writer.group(72, leader.pathType)
        writer.group(73, leader.annotationType)
        if let height = leader.textHeight { writer.group(40, height) }
        if let width = leader.textWidth { writer.group(41, width) }
        writer.group(76, leader.vertices.count)
        for vertex in leader.vertices { writer.point(10, vertex) }
        writeExtrusion(leader.extrusion)
        writer.point(211, leader.horizontalDirection)
        writer.point(212, leader.blockOffset)
        if let offset = leader.annotationOffset { writer.point(213, offset) }
        if leader.annotation != 0 { writer.handle(340, leader.annotation) }
    }

    // MARK: Hatches

    private mutating func writeHatch(_ hatch: HatchData, common: EntityCommon, space: Space) {
        writer.begin("HATCH")
        writeCommon(common, space: space)
        writer.point(10, DXF.Point(0, 0, hatch.elevation))
        writeExtrusion(hatch.extrusion)
        writer.group(2, hatch.patternName)
        writer.group(70, hatch.isSolid ? 1 : 0)
        writer.group(71, hatch.isAssociative ? 1 : 0)
        writer.group(91, hatch.paths.count)
        for path in hatch.paths { writeHatchPath(path) }
        writer.group(75, hatch.style)
        writer.group(76, hatch.patternType)
        if !hatch.isSolid {
            writer.group(52, Self.degrees(hatch.patternAngle))
            writer.group(41, hatch.patternScale)
            writer.group(77, hatch.isDouble ? 1 : 0)
            writer.group(78, hatch.patternLines.count)
            for line in hatch.patternLines {
                writer.group(53, Self.degrees(line.angle))
                writer.point2D(43, x: line.basePoint.x, y: line.basePoint.y)
                writer.point2D(45, x: line.offset.x, y: line.offset.y)
                writer.group(79, line.dashLengths.count)
                for dash in line.dashLengths { writer.group(49, dash) }
            }
        }
        if let size = hatch.pixelSize { writer.group(47, size) }
        writer.group(98, hatch.seedPoints.count)
        for seed in hatch.seedPoints { writer.point2D(10, x: seed.x, y: seed.y) }
    }

    private mutating func writeHatchPath(_ path: HatchBoundaryPath) {
        writer.group(92, path.flags)
        switch path.shape {
        case .polyline(let vertices, let closed, let hasBulges):
            writer.group(72, hasBulges ? 1 : 0)
            writer.group(73, closed ? 1 : 0)
            writer.group(93, vertices.count)
            for vertex in vertices {
                writer.point2D(10, x: vertex.point.x, y: vertex.point.y)
                if hasBulges { writer.group(42, vertex.bulge) }
            }
        case .edges(let edges):
            writer.group(93, edges.count)
            for edge in edges { writeHatchEdge(edge) }
        }
        writer.group(97, path.sourceBoundaries.count)
        for handle in path.sourceBoundaries { writer.handle(330, handle) }
    }

    private mutating func writeHatchEdge(_ edge: HatchEdge) {
        switch edge {
        case .line(let start, let end):
            writer.group(72, 1)
            writer.point2D(10, x: start.x, y: start.y)
            writer.point2D(11, x: end.x, y: end.y)
        case .circularArc(let center, let radius, let start, let end, let ccw):
            writer.group(72, 2)
            writer.point2D(10, x: center.x, y: center.y)
            writer.group(40, radius)
            writer.group(50, Self.degrees(start))
            writer.group(51, Self.degrees(end))
            writer.group(73, ccw ? 1 : 0)
        case .ellipticArc(let center, let major, let ratio, let start, let end, let ccw):
            writer.group(72, 3)
            writer.point2D(10, x: center.x, y: center.y)
            writer.point2D(11, x: major.x, y: major.y)
            writer.group(40, ratio)
            writer.group(50, Self.degrees(start))
            writer.group(51, Self.degrees(end))
            writer.group(73, ccw ? 1 : 0)
        case .spline(let spline):
            writer.group(72, 4)
            writer.group(94, spline.degree)
            writer.group(73, spline.isRational ? 1 : 0)
            writer.group(74, spline.isPeriodic ? 1 : 0)
            writer.group(95, spline.knots.count)
            writer.group(96, spline.controlPoints.count)
            for knot in spline.knots { writer.group(40, knot) }
            for (index, point) in spline.controlPoints.enumerated() {
                writer.point2D(10, x: point.x, y: point.y)
                if spline.isRational, index < spline.weights.count {
                    writer.group(42, spline.weights[index])
                }
            }
        }
    }
}
