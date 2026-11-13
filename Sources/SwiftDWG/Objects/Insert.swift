// To be ported from ACadSharp (MIT): DwgObjectReader.cs (readInsert, readMInsert, readInsertCommonData)
// The header must say so, as in Geometry.swift. See NOTICE.md.

import SwiftDXF

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct InsertData {}

extension ObjectReader {
    mutating func readInsert() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Insert")
    }

    mutating func readMInsert() throws -> DecodedEntity {
        throw NotDecodedYet(what: "MInsert")
    }
}
