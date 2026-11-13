import Foundation

/// The text encoding of a drawing's single-byte strings, from the code page the file names.
enum TextEncodings {
    /// The encoding for a DWG code page index (the 16-bit value in the file header).
    ///
    /// The Latin, Cyrillic, Greek, Turkish, Central European and Japanese pages decode correctly.
    /// The others (the DOS pages, Chinese and Korean) are not available on every platform from
    /// Foundation, so they fall back to Windows-1252, which is right for the ASCII range every one
    /// of them shares.
    static func encoding(forCodePage index: Int) -> String.Encoding {
        switch index {
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
        default: return .windowsCP1252
        }
    }
}
