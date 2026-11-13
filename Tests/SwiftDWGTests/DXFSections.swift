import Foundation

/// A record of an ASCII DXF together with the section it is in.
struct DXFSectionRecord {
    var section: String
    var record: DXFRecord
}

extension DXFGroups {
    /// Every record of an ASCII DXF in file order, with the section it is in.
    ///
    /// Unlike `records(in:)` it keeps records that have no handle, and the order, so a test can ask
    /// which entities lie between a BLOCK record and its ENDBLK.
    static func sequence(in url: URL) throws -> [DXFSectionRecord] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var out: [DXFSectionRecord] = []
        var current: DXFRecord?
        var section = ""
        var awaitingSectionName = false
        var index = 0

        func finish() {
            if let record = current {
                out.append(DXFSectionRecord(section: section, record: record))
            }
            current = nil
        }

        while index + 1 < lines.count {
            guard let code = Int(lines[index]) else {
                index += 1
                continue
            }
            let value = lines[index + 1]
            index += 2
            if code == 0 {
                if value == "SECTION" {
                    awaitingSectionName = true
                    continue
                }
                finish()
                if value == "ENDSEC" || value == "EOF" {
                    section = ""
                    continue
                }
                current = DXFRecord(type: value, groups: [])
            } else if awaitingSectionName, code == 2 {
                section = value
                awaitingSectionName = false
            } else {
                current?.groups.append((code, value))
            }
        }
        finish()
        return out
    }
}

typealias DXFGroup = (code: Int, value: String)

extension DXFRecord {
    /// The record's handle: group 5, or group 105 for a dimension style.
    var handle: UInt64? { (first(5) ?? first(105)).flatMap { UInt64($0, radix: 16) } }

    /// The groups outside every `102 {...}` block, without the `102` markers.
    var plain: [DXFGroup] {
        var depth = 0
        var out: [DXFGroup] = []
        for group in groups {
            if group.code == 102 {
                depth += group.value.hasPrefix("{") ? 1 : -1
            } else if depth == 0 {
                out.append(group)
            }
        }
        return out
    }

    /// The groups inside the `102 {name` block, up to its closing `102 }`.
    func block(_ name: String) -> [DXFGroup] {
        var inside = false
        var out: [DXFGroup] = []
        for group in groups {
            if group.code == 102 {
                if group.value == "{\(name)" {
                    inside = true
                } else if inside, group.value == "}" {
                    return out
                }
            } else if inside {
                out.append(group)
            }
        }
        return out
    }

    /// The first value of a handle group in the record's own header, before any `100` marker and
    /// outside the `102` blocks: the owner is the `330` there.
    func headerHandle(_ code: Int) -> UInt64 {
        for group in plain {
            if group.code == 100 { break }
            if group.code == code { return UInt64(group.value, radix: 16) ?? 0 }
        }
        return 0
    }

    /// The groups of one subclass: after its `100` marker up to the next one.
    func subclass(_ name: String) -> DXFRecord {
        var inside = false
        var out: [DXFGroup] = []
        for group in groups {
            if group.code == 100 {
                inside = group.value == name
            } else if inside {
                out.append(group)
            }
        }
        return DXFRecord(type: type, groups: out)
    }

    /// A handle group's value, or zero when the group is not there.
    func handleValue(_ code: Int) -> UInt64 {
        first(code).flatMap { UInt64($0, radix: 16) } ?? 0
    }
}
