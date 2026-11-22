// Derived from ACadSharp (MIT), src/ACadSharp/IO/DwgReader.cs (readTemplate) and
// src/ACadSharp/IO/DwgWriter.cs (the template section it writes). See NOTICE.md. The layout is the
// format's own, from the Open Design Specification for .dwg files.

import Foundation

/// Reads the `AcDb:Template` section, which holds the one system variable that the header section
/// does not: `$MEASUREMENT`.
enum TemplateSection {
    /// Reads `$MEASUREMENT`: 0 for English units, 1 for metric.
    ///
    /// The section starts with the length of a description, then the description, then the
    /// measurement as a short. The length counts bytes before R2007 and characters from it. Where
    /// the sample files have a description it is empty: a length of 0 before R2007, and a length of
    /// 1 followed by two zero bytes from it. The value is `nil` when the section is too short to
    /// hold the measurement or it is neither 0 nor 1, so that a damaged template section costs
    /// this one variable and nothing else.
    ///
    /// - Parameters:
    ///   - section: The bytes of `AcDb:Template`.
    ///   - version: The release the file was saved as.
    /// - Returns: The measurement, or `nil` when the section does not hold a valid one.
    static func measurement(_ section: [UInt8], version: DWG.Version) -> Int? {
        guard let length = try? section.uint16(at: 0) else { return nil }
        let bytesPerCharacter = version >= .ac1021 ? 2 : 1
        guard let value = try? section.uint16(at: 2 + Int(length) * bytesPerCharacter),
            value <= 1
        else { return nil }
        return Int(value)
    }
}
