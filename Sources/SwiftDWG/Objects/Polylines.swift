// To be ported from ACadSharp (MIT): DwgObjectReader.cs (readLWPolyline, readPolyline2D, readPolyline3D, readVertex2D, readVertex3D, readSeqend)
// The header must say so, as in Geometry.swift. See NOTICE.md.

import SwiftDXF

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct LWPolylineData {}

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct Polyline2DData {}

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct Polyline3DData {}

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct Vertex2DData {}

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct Vertex3DData {}

extension ObjectReader {
    mutating func readLWPolyline() throws -> DecodedEntity {
        throw NotDecodedYet(what: "LWPolyline")
    }

    mutating func readPolyline2D() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Polyline2D")
    }

    mutating func readPolyline3D() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Polyline3D")
    }

    mutating func readVertex2D() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Vertex2D")
    }

    mutating func readVertex3D() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Vertex3D")
    }

    mutating func readSeqend() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Seqend")
    }
}
