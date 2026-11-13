// To be ported from ACadSharp (MIT): DwgObjectReader.cs (readText, readMText, readCommonTextData)
// The header must say so, as in Geometry.swift. See NOTICE.md.

import SwiftDXF

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct TextData {}

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct MTextData {}

extension ObjectReader {
    mutating func readText() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Text")
    }

    mutating func readMText() throws -> DecodedEntity {
        throw NotDecodedYet(what: "MText")
    }
}
