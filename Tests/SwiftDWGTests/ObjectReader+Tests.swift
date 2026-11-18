@testable import SwiftDWG

extension ObjectReader {
    /// A reader for an object whose type is a fixed code, such as one built by hand, which needs
    /// none of the file's classes.
    init(
        objects: [UInt8], offset: Int, version: DWG.Version, textEncoding: String.Encoding
    ) throws {
        try self.init(
            objects: objects, offset: offset, version: version, textEncoding: textEncoding,
            classes: [:])
    }
}
