import Foundation

/// One record of an ASCII DXF as the raw group codes and values AutoCAD wrote.
///
/// Tests use this as the oracle for fields that SwiftDXF's own model does not carry. The values are
/// AutoCAD's, so they are independent of SwiftDWG.
struct DXFRecord {
    /// The record's type, such as `LINE` or `LAYER`.
    var type: String
    var groups: [(code: Int, value: String)]

    /// The first value with this group code.
    func first(_ code: Int) -> String? { groups.first { $0.code == code }?.value }

    /// Every value with this group code, in order.
    func all(_ code: Int) -> [String] { groups.filter { $0.code == code }.map(\.value) }

    func double(_ code: Int) -> Double? { first(code).flatMap { Double($0) } }

    func int(_ code: Int) -> Int? { first(code).flatMap { Int($0) } }

    /// The doubles for a run of codes such as 10, 20 and 30, from the first occurrence.
    func point(_ x: Int, _ y: Int, _ z: Int) -> (x: Double, y: Double, z: Double)? {
        guard let a = double(x), let b = double(y) else { return nil }
        return (a, b, double(z) ?? 0)
    }
}

enum DXFGroups {
    /// Every record outside the `HEADER` section that has a handle, by that handle.
    ///
    /// The handle is group 5, or 105 for a dimension style. Records without one are left out.
    static func records(in url: URL) throws -> [UInt64: DXFRecord] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var records: [UInt64: DXFRecord] = [:]
        var current: DXFRecord?
        var inHeader = false
        var index = 0

        func finish() {
            guard let record = current else { return }
            let text = record.first(5) ?? record.first(105)
            if let text, let handle = UInt64(text, radix: 16) { records[handle] = record }
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
                finish()
                if value == "SECTION" { continue }
                if value == "ENDSEC" || value == "EOF" {
                    inHeader = false
                    continue
                }
                if !inHeader { current = DXFRecord(type: value, groups: []) }
            } else if code == 2, current?.type == nil, value == "HEADER" {
                inHeader = true
            } else {
                current?.groups.append((code, value))
            }
        }
        finish()
        return records
    }
}
