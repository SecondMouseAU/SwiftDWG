// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readUCS and readMLineStyle, as far as the name). See NOTICE.md. The field order is the format's
// own, from the Open Design Specification for .dwg files.

import Foundation

extension ObjectStore {
    /// The name of the user coordinate system record with this handle, or `nil` when the file has
    /// no such record or it cannot be read.
    ///
    /// The header names a UCS by handle where DXF writes its name. Only the name is read: the
    /// record's origin and axes are not needed for that.
    func userCoordinateSystemName(_ handle: UInt64) -> String? {
        guard var opened = (try? reader(for: handle)) ?? nil, opened.type == ObjectType.ucs
        else { return nil }
        return try? opened.readTableEntryCommon().name
    }

    /// The name of the multiline style with this handle, or `nil` when the file has no such style.
    ///
    /// DXF's `$CMLSTYLE` is the name the style has in the multiline style dictionary, which can
    /// differ from the name stored in the style itself (the sample drawings keep `STANDARD` in
    /// the style and `Standard` in the dictionary, and DXF has `Standard`). So the dictionary is
    /// asked first, and the style's own name is the fallback for a style the dictionary does not
    /// list.
    ///
    /// - Parameters:
    ///   - handle: The handle of the multiline style.
    ///   - dictionary: The handle of the multiline style dictionary, or 0 when the header has none.
    /// - Returns: The name, or `nil` when the file has no such style.
    func multilineStyleName(_ handle: UInt64, dictionary: UInt64) -> String? {
        if dictionary != 0, case .dictionary(let data)? = try? tableRecord(dictionary),
            let entry = data.entries.first(where: { $0.handle == handle })
        {
            return entry.name
        }
        guard var opened = (try? reader(for: handle)) ?? nil, opened.type == ObjectType.mlineStyle
        else { return nil }
        guard (try? opened.readObjectCommon()) != nil else { return nil }
        return try? opened.readText()
    }
}
