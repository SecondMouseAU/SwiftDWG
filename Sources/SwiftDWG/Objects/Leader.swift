// To be ported from ACadSharp (MIT): DwgObjectReader.cs (readLeader)
// The header must say so, as in Geometry.swift. See NOTICE.md.

import SwiftDXF

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct LeaderData {}

extension ObjectReader {
    mutating func readLeader() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Leader")
    }
}
