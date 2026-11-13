// To be ported from ACadSharp (MIT): DwgObjectReader.cs (readEllipse, readSpline)
// The header must say so, as in Geometry.swift. See NOTICE.md.

import SwiftDXF

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct EllipseData {}

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct SplineData {}

extension ObjectReader {
    mutating func readEllipse() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Ellipse")
    }

    mutating func readSpline() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Spline")
    }
}
