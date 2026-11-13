import Foundation
import Testing

@testable import SwiftDWG

/// A header section of a drawing, with what the file header says about it.
struct HeaderInput {
    let container: Container
    var version: DWG.Version
    var maintenanceVersion: Int
    var codePage: Int
    var section: [UInt8]

    init(_ bytes: [UInt8]) throws {
        let container = try Container(bytes)
        self.container = container
        version = container.version
        maintenanceVersion = container.maintenanceVersion
        codePage = container.codePage
        section = try #require(try container.section("AcDb:Header"))
    }

    func read(_ section: [UInt8]? = nil) throws -> HeaderVariables {
        try HeaderReader.read(
            section ?? self.section, version: version, maintenanceVersion: maintenanceVersion,
            codePage: codePage)
    }

    /// The offset of the first byte of data in the section, after the sentinel, the size, and from
    /// R2010 the extra four bytes.
    var dataStart: Int { version >= .ac1024 ? 24 : 20 }

    /// The data's size in bytes, as the section declares it.
    var dataSize: Int { Int((try? section.int32(at: 16)) ?? 0) }

    /// A copy cut to `length` bytes, with the sizes in it that count bytes and bits changed to
    /// agree, so that the cut is found while the data is read and not by a check of the size.
    func cut(to length: Int) -> [UInt8] {
        var out = Array(section.prefix(length))
        let data = Swift.max(length - dataStart, 0)
        Self.put(Int32(data), into: &out, at: 16)
        if version >= .ac1021 { Self.put(Int32(data * 8), into: &out, at: dataStart) }
        return out
    }

    private static func put(_ value: Int32, into bytes: inout [UInt8], at offset: Int) {
        guard offset + 4 <= bytes.count else { return }
        for index in 0..<4 {
            bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * index))
        }
    }
}

extension HeaderInput {
    /// A drawing of the corpus (`sample_<release>.dwg`), and AutoCAD's DXF export of it when the
    /// corpus has one.
    static func corpus(_ release: String, withDXF: Bool = true) throws -> (
        HeaderInput, DXFReference?
    ) {
        let corpus = try #require(Fixtures.corpus)
        let bytes = [UInt8](
            try Data(contentsOf: corpus.appendingPathComponent("sample_\(release).dwg")))
        let dxf =
            withDXF
            ? try DXFReference(
                contentsOf: corpus.appendingPathComponent("sample_\(release)_ascii.dxf"))
            : nil
        return (try HeaderInput(bytes), dxf)
    }
}
