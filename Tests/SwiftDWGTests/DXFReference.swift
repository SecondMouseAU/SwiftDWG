import Foundation

/// AutoCAD's own ASCII DXF export of a drawing, as far as the DWG header tests need it.
///
/// That is the HEADER variables, the handles of the tables and their entries, and the entries of
/// the root dictionary. It is a reference for the DWG reader, so it shares no code with it.
struct DXFReference {
    /// One group of a DXF file: a code and the text after it.
    struct Tag {
        var code: Int
        var value: String

        var number: Double? { Double(value.trimmingCharacters(in: .whitespaces)) }
        var integer: Int? { Int(value.trimmingCharacters(in: .whitespaces)) }
        var handle: UInt64? { UInt64(value.trimmingCharacters(in: .whitespaces), radix: 16) }
    }

    /// The groups after each `9 $NAME` of the HEADER section, by variable name.
    private(set) var header: [String: [Tag]] = [:]
    /// The variable names in the order the file has them.
    private(set) var headerOrder: [String] = []
    /// The handle of each table, by the table's name (`LAYER`, `BLOCK_RECORD`, ...).
    private(set) var tableHandles: [String: UInt64] = [:]
    /// The handle of each table entry, by table name and then upper-case entry name.
    private(set) var tableEntries: [String: [String: UInt64]] = [:]
    /// The entries of the root dictionary: name to handle.
    private(set) var rootEntries: [String: UInt64] = [:]
    /// The handle of the root dictionary.
    private(set) var rootDictionary: UInt64 = 0
    /// The handle of each MLINESTYLE object, by upper-case name.
    private(set) var mlineStyles: [String: UInt64] = [:]

    /// The handle of a table entry.
    ///
    /// DXF names are not case sensitive.
    func entry(_ table: String, _ name: String) -> UInt64? {
        tableEntries[table]?[name.uppercased()]
    }

    /// The handle of an MLINESTYLE object.
    func mlineStyle(_ name: String) -> UInt64? { mlineStyles[name.uppercased()] }

    init(contentsOf url: URL) throws {
        let text = try String(contentsOf: url, encoding: .isoLatin1)
        let lines = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        var tags = [Tag]()
        var index = 0
        while index + 1 < lines.count {
            if let code = Int(lines[index].trimmingCharacters(in: .whitespaces)) {
                tags.append(Tag(code: code, value: lines[index + 1]))
            }
            index += 2
        }
        readSections(tags)
    }

    /// Splits the tags into sections and hands each to the reader for it.
    private mutating func readSections(_ tags: [Tag]) {
        var start = 0
        var name = ""
        for (index, tag) in tags.enumerated() {
            if tag.code == 0 && tag.value == "SECTION", index + 1 < tags.count {
                name = tags[index + 1].value
                start = index + 2
            } else if tag.code == 0 && tag.value == "ENDSEC" {
                let body = Array(tags[start..<index])
                switch name {
                case "HEADER": readHeader(body)
                case "TABLES": readTables(body)
                case "OBJECTS": readObjects(body)
                default: break
                }
            }
        }
    }

    private mutating func readHeader(_ tags: [Tag]) {
        var current: String?
        for tag in tags {
            if tag.code == 9 {
                current = tag.value.trimmingCharacters(in: .whitespaces)
                if let current {
                    header[current] = []
                    headerOrder.append(current)
                }
            } else if let current {
                header[current, default: []].append(Tag(code: tag.code, value: tag.value))
            }
        }
    }

    /// A group code 0 and the groups up to the next one.
    private struct Record {
        var kind: String
        var tags: [Tag]

        func first(_ codes: Int...) -> Tag? { tags.first { codes.contains($0.code) } }
    }

    private static func records(_ tags: [Tag]) -> [Record] {
        var out = [Record]()
        for tag in tags {
            if tag.code == 0 {
                out.append(Record(kind: tag.value, tags: []))
            } else if !out.isEmpty {
                out[out.count - 1].tags.append(tag)
            }
        }
        return out
    }

    /// Reads the tables, each as its own handle and then entries.
    ///
    /// An entry has its handle in group 5 (105 for a dimension style) and its name in the first
    /// group 2.
    private mutating func readTables(_ tags: [Tag]) {
        var table = ""
        for record in Self.records(tags) {
            switch record.kind {
            case "TABLE":
                table = record.first(2)?.value ?? ""
                if let handle = record.first(5)?.handle { tableHandles[table] = handle }
            case "ENDTAB":
                table = ""
            default:
                if let name = record.first(2)?.value, let handle = record.first(5, 105)?.handle {
                    tableEntries[table, default: [:]][name.uppercased()] = handle
                }
            }
        }
    }

    /// The root dictionary, which is the dictionary with no owner, and the MLINESTYLE objects.
    private mutating func readObjects(_ tags: [Tag]) {
        for record in Self.records(tags) {
            switch record.kind {
            case "DICTIONARY" where rootDictionary == 0 && record.first(330)?.integer == 0:
                rootDictionary = record.first(5)?.handle ?? 0
                var name: String?
                for tag in record.tags {
                    if tag.code == 3 { name = tag.value }
                    if tag.code == 350 || tag.code == 360, let name {
                        rootEntries[name] = tag.handle
                    }
                }
            case "MLINESTYLE":
                if let name = record.first(2)?.value, let handle = record.first(5)?.handle {
                    mlineStyles[name.uppercased()] = handle
                }
            default:
                break
            }
        }
    }
}
