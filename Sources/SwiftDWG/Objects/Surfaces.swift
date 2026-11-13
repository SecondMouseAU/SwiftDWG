// To be ported from ACadSharp (MIT): DwgObjectReader.cs (readSolid, read3dFace)
// The header must say so, as in Geometry.swift. See NOTICE.md.

import SwiftDXF

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct SolidData {}

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct Face3DData {}

extension ObjectReader {
    mutating func readSolid() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Solid")
    }

    mutating func readFace3D() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Face3D")
    }
}
