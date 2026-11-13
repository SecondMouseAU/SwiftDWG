// Derived from ACadSharp (MIT), the table of code pages in src/ACadSharp/CadUtils.cs, which is
// indexed by the number a DWG file header keeps for its code page. See NOTICE.md.

import Foundation

/// How a drawing's single-byte text is encoded, from the code page number in its file header.
enum CodePage {
    /// The encoding for a code page number, or `nil` when this package has none for it.
    ///
    /// A caller that gets `nil` should keep the Windows-1252 default.
    ///
    /// The numbers are an index into a list the format fixes, so 30 is Windows-1252. Only the code
    /// pages Foundation decodes on every platform are listed. A drawing in another one, such as the
    /// DOS and the double-byte Asian pages, reads as Windows-1252 until they are added.
    static func encoding(for number: Int) -> String.Encoding? {
        switch number {
        case 1: return .ascii
        case 2: return .isoLatin1
        case 3: return .isoLatin2
        case 22, 38: return .shiftJIS
        case 23: return .macOSRoman
        case 28: return .windowsCP1250
        case 29: return .windowsCP1251
        case 30: return .windowsCP1252
        case 32: return .windowsCP1253
        case 33: return .windowsCP1254
        default: return nil
        }
    }
}
