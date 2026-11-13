// Derived from ACadSharp (MIT), src/ACadSharp/IO/DwgReader.cs (the file header, page map, section
// map and section page readers) and src/ACadSharp/IO/DWG/FileHeaders/. See NOTICE.md. The layout
// is the format's own, from the Open Design Specification for .dwg files.

import Foundation

/// The outer structure of a DWG: where its sections are, and their bytes.
///
/// A DWG is a set of named sections (header variables, classes, the object map, the objects). From
/// R2004 they are cut into pages that are compressed and scattered through the file, and mapped by
/// tables that are themselves compressed. The reader here puts a section back together.
struct Container {
    /// The release the file was saved as.
    let version: DWG.Version
    /// The whole file.
    let data: [UInt8]
    /// The Windows code page the drawing's single-byte text is in, such as 30 for 1252.
    private(set) var codePage: Int = 0
    /// The AutoCAD maintenance release that wrote the file.
    private(set) var maintenanceVersion: Int = 0
    /// Where the preview image starts, or -1.
    private(set) var previewAddress: Int = -1

    /// A section of an R2004 or later file.
    struct Descriptor {
        var name = ""
        /// The size of the whole section once its pages are put together.
        var size: UInt64 = 0
        /// The largest size one page decompresses to.
        var pageSize: UInt64 = 0x7400
        /// Whether pages are compressed (the file says 2) or stored as they are (1).
        var isCompressed = true
        var pages: [Page] = []
    }

    /// One page of a section.
    struct Page {
        /// The page's number in the file's page map.
        var number = 0
        /// Where the page's header starts in the file.
        var seeker = 0
        /// How many bytes it decompresses to.
        var size: UInt64 = 0
        /// A page that was never written because it is all zeros.
        var isEmpty = false
    }

    /// A section of an R13 to R2000 file: a position and a size.
    struct Locator {
        var seeker: Int
        var size: Int
    }

    private var descriptors: [String: Descriptor] = [:]
    private var locators: [Int: Locator] = [:]
    private var sectionsR2007: [String: SectionR2007] = [:]
    private var pagesR2007: [Int: Locator] = [:]

    /// The names of the sections the file has.
    var sectionNames: [String] {
        switch version {
        case .ac1012, .ac1014, .ac1015:
            let named = Self.locatorNumbers.filter { locators[$0.value] != nil }.map(\.key)
            return (named + ["AcDb:AcDbObjects"]).sorted()
        case .ac1021:
            return sectionsR2007.keys.sorted()
        default:
            return descriptors.keys.sorted()
        }
    }

    init(_ data: [UInt8]) throws {
        guard let code = String(bytes: data.prefix(6), encoding: .ascii), code.hasPrefix("AC"),
            DWG.looksLikeDWG(Data(data.prefix(6)))
        else { throw DWG.Error.notADWG }
        guard let version = DWG.Version(code: code) else {
            throw DWG.Error.unsupportedVersion(code)
        }
        self.version = version
        self.data = data
        switch version {
        case .ac1012, .ac1014, .ac1015:
            try readHeaderAC15()
        case .ac1018, .ac1024, .ac1027, .ac1032:
            try readHeaderAC18()
        case .ac1021:
            try readHeaderAC21()
        default:
            throw DWG.Error.unsupportedVersion(code)
        }
    }

    // MARK: R13 to R2000

    /// The section numbers an R13 to R2000 header lists them by.
    ///
    /// The objects themselves are not a section but the rest of the file.
    private static let locatorNumbers: [String: Int] = [
        "AcDb:Header": 0, "AcDb:Classes": 1, "AcDb:Handles": 2, "AcDb:ObjFreeSpace": 3,
        "AcDb:Template": 4, "AcDb:AuxHeader": 5,
    ]

    private mutating func readHeaderAC15() throws {
        maintenanceVersion = Int(try byte(at: 0x0B))
        previewAddress = Int(try data.int32(at: 0x0D))
        codePage = Int(try data.uint16(at: 0x13))
        // A count of records, each a number, a position and a size, then a CRC and a sentinel.
        let count = Int(try data.int32(at: 0x15))
        guard count >= 0, count < 256 else { throw DWG.Error.invalid("\(count) section locators") }
        var position = 0x19
        for _ in 0..<count {
            let number = Int(try byte(at: position))
            let seeker = Int(try data.int32(at: position + 1))
            let size = Int(try data.int32(at: position + 5))
            position += 9
            guard seeker >= 0, size >= 0, seeker + size <= data.count else {
                throw DWG.Error.invalid("section \(number) lies outside the file")
            }
            locators[number] = Locator(seeker: seeker, size: size)
        }
    }

    // MARK: R2004 and later

    /// The magic bytes that the 0x6C encrypted bytes of the R2004 header are combined with.
    private static func decrypted(_ encrypted: ArraySlice<UInt8>) -> [UInt8] {
        var seed: Int32 = 1
        return encrypted.map { byte in
            seed = seed &* 0x343FD &+ 0x269EC3
            return byte ^ UInt8(truncatingIfNeeded: seed >> 16)
        }
    }

    private mutating func readHeaderAC18() throws {
        maintenanceVersion = Int(try byte(at: 0x0B))
        previewAddress = Int(try data.int32(at: 0x0D))
        codePage = Int(try data.uint16(at: 0x13))

        guard data.count >= 0x80 + 0x6C else { throw DWG.Error.truncated("the file header") }
        let header = Self.decrypted(data[0x80..<(0x80 + 0x6C)])
        let fileID = String(bytes: header[0..<11], encoding: .ascii)
        guard fileID == "AcFssFcAJMB" else {
            throw DWG.Error.invalid("the file header is not valid (file id \(fileID ?? "?"))")
        }
        let pageMapAddress = Int(try header.uint64(at: 0x54)) + 0x100
        let sectionMapID = Int(try header.uint32(at: 0x5C))

        let pageRecords = try readPageMap(at: pageMapAddress)
        guard let sectionMap = pageRecords[sectionMapID] else {
            throw DWG.Error.invalid("the section map is not in the page map")
        }
        try readSectionMap(at: sectionMap.seeker, pages: pageRecords)
    }

    /// Reads the page map: for each page number, where it starts and how large it is.
    private func readPageMap(at address: Int) throws -> [Int: Locator] {
        let map = try systemPage(at: address)
        var records: [Int: Locator] = [:]
        var position = 0
        var total = 0x100
        while position + 8 <= map.count {
            let number = Int(try map.int32(at: position))
            let size = Int(try map.int32(at: position + 4))
            position += 8
            if number >= 0 {
                records[number] = Locator(seeker: total, size: size)
            } else {
                // A gap in the file: parent, left, right and a zero follow.
                position += 16
            }
            total += size
        }
        return records
    }

    /// Reads the section map into descriptors, with the pages each section is made of.
    private mutating func readSectionMap(at address: Int, pages: [Int: Locator]) throws {
        let map = try systemPage(at: address)
        let count = Int(try map.int32(at: 0))
        guard count >= 0, count < 4096 else { throw DWG.Error.invalid("section count \(count)") }
        var position = 20

        for _ in 0..<count {
            var descriptor = Descriptor()
            descriptor.size = try map.uint64(at: position)
            let pageCount = Int(try map.int32(at: position + 8))
            // A negative size is clamped to 0, which the check below refuses; converting it
            // straight to UInt64 would trap.
            descriptor.pageSize = UInt64(max(0, try map.int32(at: position + 12)))
            descriptor.isCompressed = try map.int32(at: position + 20) == 2
            // The name starts 32 bytes in; the reads above only reach byte 24.
            guard position + 32 <= map.count else { throw DWG.Error.truncated("a section name") }
            let nameBytes = map[(position + 32)..<min(position + 96, map.count)]
            descriptor.name = String(decoding: nameBytes.prefix { $0 != 0 }, as: UTF8.self)
            position += 96

            guard pageCount >= 0, pageCount <= map.count / 16, descriptor.pageSize > 0,
                descriptor.size <= 1 << 31
            else {
                throw DWG.Error.invalid("section \(descriptor.name) has a size that is not valid")
            }

            var covered: UInt64 = 0
            for _ in 0..<pageCount {
                let number = Int(try map.int32(at: position))
                let offset = try map.uint64(at: position + 8)
                position += 16
                // Pages that are all zeros are not written; fill the gap before this one.
                while covered < offset {
                    descriptor.pages.append(Page(size: descriptor.pageSize, isEmpty: true))
                    covered += descriptor.pageSize
                }
                guard let locator = pages[number] else {
                    throw DWG.Error.invalid("page \(number) is not in the page map")
                }
                descriptor.pages.append(
                    Page(number: number, seeker: locator.seeker, size: descriptor.pageSize))
                covered += descriptor.pageSize
            }
            while covered < descriptor.size {
                descriptor.pages.append(Page(size: descriptor.pageSize, isEmpty: true))
                covered += descriptor.pageSize
            }
            let remainder = descriptor.size % descriptor.pageSize
            if remainder > 0, !descriptor.pages.isEmpty {
                descriptor.pages[descriptor.pages.count - 1].size = remainder
            }
            descriptors[descriptor.name] = descriptor
        }
    }

    /// Reads a system page (the page map or the section map): a 20-byte header, then compressed
    /// data.
    private func systemPage(at address: Int) throws -> [UInt8] {
        let size = Int(try data.int32(at: address + 4))
        guard size >= 0, size <= 1 << 28 else {
            throw DWG.Error.invalid("system page size \(size)")
        }
        return try LZ77.decompressAC18(data, from: address + 20, limit: size)
    }

    /// The bytes of a section, with its pages decompressed and joined, or `nil` if the file has no
    /// section of that name.
    func section(_ name: String) throws -> [UInt8]? {
        switch version {
        case .ac1012, .ac1014, .ac1015:
            // The objects are addressed by their position in the whole file.
            if name == "AcDb:AcDbObjects" { return data }
            guard let number = Self.locatorNumbers[name], let locator = locators[number] else {
                return nil
            }
            return Array(data[locator.seeker..<(locator.seeker + locator.size)])
        case .ac1018, .ac1024, .ac1027, .ac1032:
            guard let descriptor = descriptors[name] else { return nil }
            return try assemble(descriptor)
        case .ac1021:
            guard let section = sectionsR2007[name] else { return nil }
            return try assembleR2007(section)
        default:
            throw DWG.Error.unsupportedVersion(version.code)
        }
    }

    private func assemble(_ descriptor: Descriptor) throws -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(Int(min(descriptor.size, 1 << 28)))
        for page in descriptor.pages {
            if page.isEmpty {
                out.append(contentsOf: [UInt8](repeating: 0, count: Int(page.size)))
                continue
            }
            // The page header is 32 bytes, each long masked with a value from its own position.
            // The long at 0x08 is the size of the data that follows, and the one at 0x0C is the
            // page's size in the file, padding included. Neither is the decompressed size, which
            // is the section's page size: a final page decompresses to a whole page, with
            // padding after the section's declared size.
            let mask =
                Int32(truncatingIfNeeded: 0x4164_536B) ^ Int32(truncatingIfNeeded: page.seeker)
            let dataSize = Int(try data.int32(at: page.seeker + 8) ^ mask)
            let start = page.seeker + 32
            guard dataSize >= 0, start + dataSize <= data.count else {
                throw DWG.Error.invalid(
                    "page \(page.number) of \(descriptor.name) has a bad header")
            }
            if descriptor.isCompressed {
                let limit = Int(min(descriptor.pageSize, 1 << 24))
                out.append(contentsOf: try LZ77.decompressAC18(data, from: start, limit: limit))
            } else {
                out.append(contentsOf: data[start..<(start + dataSize)])
            }
        }
        return out
    }

    private func byte(at offset: Int) throws -> UInt8 {
        guard offset >= 0, offset < data.count else { throw DWG.Error.truncated("the file header") }
        return data[offset]
    }

    // MARK: R2007

    /// A section of an R2007 file.
    ///
    /// Each page says how large it is stored and decompressed.
    struct SectionR2007 {
        var name = ""
        /// 4 for pages that are Reed-Solomon coded.
        var encoding: UInt64 = 0
        var pages: [PageR2007] = []
    }

    struct PageR2007 {
        var number = 0
        var decompressedSize = 0
        var compressedSize = 0
        var isEmpty = false
    }

    /// Where the pages and the sections are described, and how they are coded.
    private mutating func readHeaderAC21() throws {
        maintenanceVersion = Int(try byte(at: 0x0B))
        previewAddress = Int(try data.int32(at: 0x0D))
        codePage = Int(try data.uint16(at: 0x13))

        // 0x400 bytes at 0x80 hold the first 0x3D8 bytes of data, spread in three interleaved
        // blocks of 239 with error-correction bytes (which are not used here).
        guard data.count >= 0x480 else { throw DWG.Error.truncated("the R2007 file header") }
        let decoded = Self.deinterleave(
            Array(data[0x80..<0x480]), outputSize: 3 * 239, factor: 3, blockSize: 239)
        let compressedLength = Int(try decoded.int32(at: 24))
        guard compressedLength > 0, compressedLength + 32 <= decoded.count else {
            throw DWG.Error.invalid("R2007 header of \(compressedLength) bytes")
        }
        let meta = try LZ77AC21.decompress(
            decoded, offset: 32, length: compressedLength, outputSize: 0x110)

        let pageMapFactor = try meta.uint64(at: 0x18)
        let pageMapOffset = try meta.uint64(at: 0x38)
        let pageMapCompressed = try meta.uint64(at: 0x50)
        let pageMapSize = try meta.uint64(at: 0x58)
        let sectionMapID = Int(try meta.uint64(at: 0xC0))
        let sectionMapCompressed = try meta.uint64(at: 0xB0)
        let sectionMapSize = try meta.uint64(at: 0xC8)
        let sectionMapFactor = try meta.uint64(at: 0xD8)

        let pageMap = try pageBufferR2007(
            offset: pageMapOffset, compressed: pageMapCompressed, size: pageMapSize,
            factor: pageMapFactor, blockSize: 0xEF)
        var position = 0
        var seeker = 0
        while position + 16 <= pageMap.count {
            let size = Int(try pageMap.uint64(at: position))
            let identifier = abs(Int(Int64(bitPattern: try pageMap.uint64(at: position + 8))))
            position += 16
            guard size >= 0, size <= 1 << 30 else { throw DWG.Error.invalid("page size \(size)") }
            pagesR2007[identifier] = Locator(seeker: seeker, size: size)
            seeker += size
        }

        guard let sectionMapPage = pagesR2007[sectionMapID] else {
            throw DWG.Error.invalid("the section map is not in the page map")
        }
        let sectionMap = try pageBufferR2007(
            offset: UInt64(sectionMapPage.seeker), compressed: sectionMapCompressed,
            size: sectionMapSize, factor: sectionMapFactor, blockSize: 239)
        try readSectionMapR2007(sectionMap)
    }

    private mutating func readSectionMapR2007(_ map: [UInt8]) throws {
        var position = 0
        while position + 0x40 <= map.count {
            var section = SectionR2007()
            let maxPageSize = try map.uint64(at: position + 0x08)
            section.encoding = try map.uint64(at: position + 0x30)
            let nameLength = Int(Int64(bitPattern: try map.uint64(at: position + 0x20)))
            let pageCount = Int(try map.uint64(at: position + 0x38))
            position += 0x40
            guard nameLength >= 0, nameLength <= 1 << 12, pageCount >= 0,
                pageCount <= map.count / 56
            else { throw DWG.Error.invalid("R2007 section map entry") }
            if nameLength > 0 {
                guard position + nameLength <= map.count else {
                    throw DWG.Error.truncated("an R2007 section name")
                }
                let units = stride(from: position, to: position + nameLength - 1, by: 2).map {
                    UInt16(map[$0]) | UInt16(map[$0 + 1]) << 8
                }
                section.name = String(decoding: units, as: UTF16.self)
                    .replacingOccurrences(of: "\0", with: "")
                position += nameLength
            }
            var covered: UInt64 = 0
            for _ in 0..<pageCount {
                let offset = try map.uint64(at: position)
                var page = PageR2007()
                page.number = Int(Int64(bitPattern: try map.uint64(at: position + 16)))
                page.decompressedSize = Int(try map.uint64(at: position + 24))
                page.compressedSize = Int(try map.uint64(at: position + 32))
                position += 56
                guard page.decompressedSize >= 0, page.decompressedSize <= 1 << 28,
                    page.compressedSize >= 0, page.compressedSize <= 1 << 28
                else { throw DWG.Error.invalid("R2007 page of a size that is not valid") }
                if covered < offset {
                    // A page of zeros that was not written.
                    section.pages.append(
                        PageR2007(
                            decompressedSize: Int(min(offset - covered, 1 << 28)), isEmpty: true))
                }
                section.pages.append(page)
                covered = offset + UInt64(page.decompressedSize)
            }
            _ = maxPageSize
            if nameLength > 0 { sectionsR2007[section.name] = section }
        }
    }

    /// Reads a page that holds a map: Reed-Solomon coded, then compressed.
    private func pageBufferR2007(
        offset: UInt64, compressed: UInt64, size: UInt64, factor: UInt64, blockSize: Int
    ) throws -> [UInt8] {
        let padded = (compressed + 7) & ~7
        guard padded <= 1 << 28, factor <= 1 << 8, size <= 1 << 28 else {
            throw DWG.Error.invalid("R2007 map page with a size that is not valid")
        }
        let total = Int(padded * factor)
        let blocks = (total + blockSize - 1) / blockSize
        let start = 0x480 + Int(min(offset, 1 << 40))
        let raw = Self.slice(data, from: start, length: blocks * 255)
        let coded = Self.deinterleave(raw, outputSize: total, factor: blocks, blockSize: blockSize)
        return try LZ77AC21.decompress(
            coded, offset: 0, length: Int(compressed), outputSize: Int(size))
    }

    private func assembleR2007(_ section: SectionR2007) throws -> [UInt8] {
        var out = [UInt8]()
        for page in section.pages {
            if page.isEmpty {
                out.append(contentsOf: [UInt8](repeating: 0, count: page.decompressedSize))
                continue
            }
            guard let locator = pagesR2007[page.number] else {
                throw DWG.Error.invalid("page \(page.number) is not in the page map")
            }
            var bytes = Self.slice(data, from: 0x480 + locator.seeker, length: locator.size)
            if section.encoding == 4 {
                let padded = (page.compressedSize + 7) & ~7
                let blocks = (padded + 250) / 251
                bytes = Self.deinterleave(
                    bytes, outputSize: blocks * 251, factor: blocks, blockSize: 251)
            }
            if page.compressedSize != page.decompressedSize {
                bytes = try LZ77AC21.decompress(
                    bytes, offset: 0, length: page.compressedSize, outputSize: page.decompressedSize
                )
            }
            guard bytes.count >= page.decompressedSize else {
                throw DWG.Error.truncated("page \(page.number) of \(section.name)")
            }
            out.append(contentsOf: bytes[0..<page.decompressedSize])
        }
        return out
    }

    /// Undoes the interleaving of Reed-Solomon coded data.
    ///
    /// Byte `i` of block `n` is at `n + i * factor`. The error-correction bytes are dropped.
    private static func deinterleave(
        _ encoded: [UInt8], outputSize: Int, factor: Int, blockSize: Int
    ) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: outputSize)
        var index = 0
        var length = outputSize
        for block in 0..<factor where block < encoded.count {
            let size = min(length, blockSize)
            length -= size
            var source = block
            for _ in 0..<size {
                if source < encoded.count { out[index] = encoded[source] }
                index += 1
                source += factor
            }
        }
        return out
    }

    /// `length` bytes from `start`, with zeros for any that lie past the end of the data.
    private static func slice(_ data: [UInt8], from start: Int, length: Int) -> [UInt8] {
        guard start >= 0, length > 0 else { return [] }
        let end = min(start + length, data.count)
        var out = start < end ? Array(data[start..<end]) : []
        if out.count < length {
            out.append(contentsOf: [UInt8](repeating: 0, count: length - out.count))
        }
        return out
    }
}
