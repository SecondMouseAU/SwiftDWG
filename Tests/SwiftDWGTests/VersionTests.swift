import Foundation
import Testing

@testable import SwiftDWG

@Suite("DWG version")
struct VersionTests {
    private func header(_ code: String) -> Data {
        Data(code.utf8) + Data(repeating: 0, count: 20)
    }

    @Test("every known code is read back as its version")
    func knownCodes() {
        for version in DWG.Version.allCases {
            #expect(DWG.version(of: header(version.code)) == version)
            #expect(DWG.looksLikeDWG(header(version.code)))
        }
    }

    @Test("a newer release is a DWG with no known version")
    func newerRelease() {
        let data = header("AC1099")
        #expect(DWG.looksLikeDWG(data))
        #expect(DWG.version(of: data) == nil)
    }

    @Test("things that are not a DWG are refused")
    func notDWG() {
        #expect(!DWG.looksLikeDWG(Data()))
        #expect(!DWG.looksLikeDWG(Data("AC10".utf8)))
        #expect(!DWG.looksLikeDWG(Data("  0\nSECTION\n  2\nHEADER\n".utf8)))
        #expect(!DWG.looksLikeDWG(Data("ACXXXX".utf8)))
        #expect(!DWG.looksLikeDWG(Data("AC10 5".utf8)))
        #expect(DWG.version(of: Data("PK\u{3}\u{4}....".utf8)) == nil)
    }

    @Test("versions are ordered oldest to newest, and named by release")
    func ordering() {
        #expect(DWG.Version.ac1009 < DWG.Version.ac1015)
        #expect(DWG.Version.ac1018 < DWG.Version.ac1032)
        #expect(DWG.Version.allCases.sorted() == DWG.Version.allCases)
        #expect(DWG.Version.ac1032.release == "2018")
        #expect(DWG.Version(code: "AC1021")?.release == "2007")
        #expect(DWG.Version(code: "AC9999") == nil)
    }
}
