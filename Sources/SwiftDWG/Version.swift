import Foundation

/// DWG, AutoCAD's native binary drawing format.
public enum DWG {
    /// The release of the format that a file was saved as, named by the code at its start.
    ///
    /// The first six bytes of every DWG from AutoCAD Release 10 onward are an ASCII code such as
    /// `AC1032`. Which releases a reader decodes is a separate question from which it names.
    public enum Version: String, CaseIterable, Comparable, Sendable {
        /// AutoCAD Release 10.
        case ac1006 = "AC1006"
        /// AutoCAD Release 11 and 12.
        case ac1009 = "AC1009"
        /// AutoCAD Release 13.
        case ac1012 = "AC1012"
        /// AutoCAD Release 14.
        case ac1014 = "AC1014"
        /// AutoCAD 2000, 2000i and 2002.
        case ac1015 = "AC1015"
        /// AutoCAD 2004, 2005 and 2006.
        case ac1018 = "AC1018"
        /// AutoCAD 2007, 2008 and 2009.
        case ac1021 = "AC1021"
        /// AutoCAD 2010, 2011 and 2012.
        case ac1024 = "AC1024"
        /// AutoCAD 2013 to 2017.
        case ac1027 = "AC1027"
        /// AutoCAD 2018 and later.
        case ac1032 = "AC1032"

        /// The code as the file writes it, such as `AC1032`.
        public var code: String { rawValue }

        /// The AutoCAD release name, such as `2018`.
        public var release: String {
            switch self {
            case .ac1006: return "R10"
            case .ac1009: return "R12"
            case .ac1012: return "R13"
            case .ac1014: return "R14"
            case .ac1015: return "2000"
            case .ac1018: return "2004"
            case .ac1021: return "2007"
            case .ac1024: return "2010"
            case .ac1027: return "2013"
            case .ac1032: return "2018"
            }
        }

        /// A version from its code, or `nil` for a code this package does not know.
        public init?(code: String) {
            self.init(rawValue: code)
        }

        public static func < (lhs: Version, rhs: Version) -> Bool {
            allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
        }
    }

    /// The version a file was saved as, from its first bytes, or `nil` if it is not a DWG this
    /// package knows.
    public static func version(of data: Data) -> Version? {
        guard let code = versionCode(of: data) else { return nil }
        return Version(code: code)
    }

    /// Whether the bytes start like a DWG: `AC` and four digits, a known version or not.
    ///
    /// A DWG from a release newer than the ones this package names is still reported as a DWG,
    /// with `version(of:)` returning `nil`, so a caller can say "newer than I can read" and not
    /// "not a drawing".
    public static func looksLikeDWG(_ data: Data) -> Bool {
        versionCode(of: data) != nil
    }

    /// The six-character code at the start of the file when it has the shape `AC` plus four digits.
    private static func versionCode(of data: Data) -> String? {
        guard data.count >= 6 else { return nil }
        let bytes = data.prefix(6)
        let code = String(decoding: bytes, as: UTF8.self)
        guard code.hasPrefix("AC") else { return nil }
        guard code.dropFirst(2).allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return code
    }
}
