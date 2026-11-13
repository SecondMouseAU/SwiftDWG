extension ObjectType {
    /// The DXF name of an object type that is an entity, or `nil` for one that is not.
    ///
    /// A class number is an entity when the file's class of that number makes entities.
    static func typeName(_ type: Int, classes: [Int: DWGClass]) -> String? {
        if type >= firstClass {
            guard let found = classes[type], found.itemClassID == 0x1F2 else { return nil }
            return found.dxfName
        }
        switch type {
        case attrib: return "ATTRIB"
        case attdef: return "ATTDEF"
        case vertexMesh, vertexPFace, vertexPFaceFace: return "VERTEX"
        case polylinePFace: return "POLYFACE_MESH"
        case polylineMesh: return "POLYGON_MESH"
        case shape: return "SHAPE"
        case viewport: return "VIEWPORT"
        case region: return "REGION"
        case solid3D: return "3DSOLID"
        case body: return "BODY"
        case ray: return "RAY"
        case xline: return "XLINE"
        case oleFrame, ole2Frame: return "OLE2FRAME"
        case tolerance: return "TOLERANCE"
        case mline: return "MLINE"
        default: return nil
        }
    }

    /// The DXF name of an entity type that `readEntity` decodes.
    static func decodedTypeName(_ type: Int) -> String? {
        switch type {
        case line: return "LINE"
        case circle: return "CIRCLE"
        case arc: return "ARC"
        case point: return "POINT"
        case text: return "TEXT"
        case mtext: return "MTEXT"
        case insert, minsert: return "INSERT"
        case ellipse: return "ELLIPSE"
        case spline: return "SPLINE"
        case lwpolyline: return "LWPOLYLINE"
        case polyline2D, polyline3D: return "POLYLINE"
        case vertex2D, vertex3D: return "VERTEX"
        case seqend: return "SEQEND"
        case solid: return "SOLID"
        case trace: return "TRACE"
        case face3D: return "3DFACE"
        case dimensionOrdinate, dimensionLinear, dimensionAligned, dimensionAngular3Point,
            dimensionAngular2Line, dimensionRadius, dimensionDiameter:
            return "DIMENSION"
        case leader: return "LEADER"
        case hatch: return "HATCH"
        default: return nil
        }
    }

    /// Whether an object of this type is an entity: one that `typeName(_:classes:)` or
    /// `decodedTypeName(_:)` names.
    ///
    /// `BLOCK` and `ENDBLK` are not in either list, as the entities of a block do not include them.
    static func isEntity(_ type: Int, classes: [Int: DWGClass]) -> Bool {
        typeName(type, classes: classes) != nil || decodedTypeName(type) != nil
    }
}
