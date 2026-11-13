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

    /// The names of the sections an R2004 or later file has.
    var sectionNames: [String] { descriptors.keys.sorted() }

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
        case .ac1018, .ac1024, .ac1027, .ac1032:
            try readHeaderAC18()
        default:
            throw DWG.Error.unsupportedVersion(code)
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
            descriptor.pageSize = UInt64(try map.int32(at: position + 12))
            descriptor.isCompressed = try map.int32(at: position + 20) == 2
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
        case .ac1018, .ac1024, .ac1027, .ac1032:
            guard let descriptor = descriptors[name] else { return nil }
            return try assemble(descriptor)
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
}
