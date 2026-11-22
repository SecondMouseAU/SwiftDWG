import Foundation
import Testing

@testable import SwiftDWG

/// A release number, `major.minor.patch` and nothing else, compared as numbers.
private struct ReleaseNumber: Comparable {
    let text: String
    let parts: [Int]

    /// The number from text of exactly three dot-separated runs of digits, or `nil`.
    init?(_ text: String) {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }),
                let value = Int(piece)
            else { return nil }
            parts.append(value)
        }
        self.text = text
        self.parts = parts
    }

    static func < (lhs: ReleaseNumber, rhs: ReleaseNumber) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}

@Suite("Reader version")
struct ReaderVersionTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Runs a program and returns its exit status and output, or `nil` if it cannot be started.
    private func run(_ arguments: [String]) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @Test("a release number is exactly major.minor.patch, compared as numbers")
    func releaseNumbers() {
        #expect(ReleaseNumber("0.2.0") != nil)
        #expect(ReleaseNumber("10.0.12") != nil)
        for bad in ["", "0.2", "0.2.0.1", "v0.2.0", "0.2.0-beta.1", "0..1", "0.2.x", "-1.0.0"] {
            #expect(ReleaseNumber(bad) == nil, "\(bad) is not a release number")
        }
        if let nine = ReleaseNumber("0.9.0"), let ten = ReleaseNumber("0.10.0") {
            #expect(nine < ten)
        }
        if let older = ReleaseNumber("0.2.9"), let newer = ReleaseNumber("0.3.0") {
            #expect(older < newer)
        }
    }

    @Test("the reader version is a plain major.minor.patch string")
    func format() {
        #expect(
            ReleaseNumber(DWG.readerVersion) != nil, "\(DWG.readerVersion) is not major.minor.patch"
        )
    }

    @Test("the reader version is not older than the latest release tag")
    func notOlderThanLatestTag() {
        // Needs git, a checkout and its tags: skipped without them, as a CI checkout has none
        // unless it fetches them. Newer than the latest tag is fine, since the constant is set
        // before a release is tagged.
        guard let result = run(["git", "-C", Self.root.path, "tag", "--list"]), result.status == 0
        else { return }
        let tags = result.output.split(whereSeparator: \.isNewline).compactMap {
            ReleaseNumber(String($0))
        }
        guard let latest = tags.max(), let current = ReleaseNumber(DWG.readerVersion) else {
            return
        }
        #expect(
            current >= latest,
            "DWG.readerVersion \(DWG.readerVersion) is older than the tag \(latest.text)")
    }

    @Test("the release script reads the constant from the source and compares it with a tag")
    func releaseScript() {
        let script = Self.root.appendingPathComponent("Scripts/check-reader-version.sh").path
        guard FileManager.default.isExecutableFile(atPath: script) else { return }
        guard let printed = run([script]), printed.status == 0 else {
            Issue.record("the script cannot read the constant from the source")
            return
        }
        #expect(printed.output.trimmingCharacters(in: .whitespacesAndNewlines) == DWG.readerVersion)
        if let same = run([script, DWG.readerVersion]) {
            #expect(same.status == 0, "\(same.output)")
        }
        if let other = run([script, "99.0.0"]) {
            #expect(other.status != 0, "a tag that differs must fail the check")
        }
        if let ref = run([script, "refs/tags/\(DWG.readerVersion)"]) {
            #expect(ref.status == 0, "\(ref.output)")
        }
    }
}
