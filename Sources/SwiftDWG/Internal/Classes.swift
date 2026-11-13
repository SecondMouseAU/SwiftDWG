// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgClassesReader.cs. See
// NOTICE.md. The layout is the format's own, from the Open Design Specification for .dwg files.

/// A class a file defines for its custom objects and entities.
///
/// The object type codes from 500 up are not fixed: each is the number of one of these, and the
/// DXF name says what it is, such as `IMAGE` or `MULTILEADER`.
struct DWGClass: Equatable {
    var number: Int
    var proxyFlags: Int
    var applicationName: String
    var cppClassName: String
    var dxfName: String
    var wasZombie: Bool
    /// 0x1F2 for a class that makes entities, 0x1F3 for one that makes objects.
    var itemClassID: Int
    var instanceCount: Int
}

/// Reads the `AcDb:Classes` section.
enum ClassesReader {
    /// The classes of a file, by class number.
    static func read(
        _ section: [UInt8], version: DWG.Version, maintenanceVersion: Int,
        textEncoding: String.Encoding
    ) throws -> [Int: DWGClass] {
        var main = BitReader(section, version: version)
        main.textEncoding = textEncoding

        // The sentinel, then the size of the class data in bytes.
        _ = try main.readBytes(16)
        let size = Int(try main.readRawLong())
        guard size >= 0 else { throw DWG.Error.invalid("class data size \(size)") }
        var end = main.position + size * 8

        // R2010 and later, when the maintenance version says so: a long that is not used here.
        if (version >= .ac1024 && maintenanceVersion > 3) || version > .ac1027 {
            _ = try main.readRawLong()
        }

        var text = main
        var flagBit = 0
        var hasText = false
        if version >= .ac1021 {
            // The class data's size in bits, counted from where that size starts.
            let sizeBit = main.position
            flagBit = sizeBit + Int(try main.readRawLong()) - 1
            let afterSize = main.position
            if let start = try main.stringStreamStart(flagBit: flagBit) {
                end = start
                try text.seek(toBit: start)
                hasText = true
            } else {
                end = main.bitCount
            }
            try main.seek(toBit: afterSize)
            _ = try main.readBitLong()
            _ = try main.readBit()
        }

        if version == .ac1018 {
            // The highest class number, two zero bytes and a bit that is set.
            _ = try main.readBitShort()
            _ = try main.readByte()
            _ = try main.readByte()
            _ = try main.readBit()
        }

        var classes: [Int: DWGClass] = [:]
        // The data is a run of classes until it is used up. Before R2007 the data ends at a byte
        // boundary and its last byte can hold padding bits, so a partly read byte counts as read.
        // Bound the run, since the size is the file's.
        func hasMore() -> Bool {
            version >= .ac1021 ? main.position < end : (main.position + 7) / 8 < end / 8
        }
        while hasMore(), classes.count < 1 << 16 {
            let number = Int(try main.readBitShort())
            let proxyFlags = Int(try main.readBitShort())
            let application = try readText(&main, &text, hasText)
            let cppName = try readText(&main, &text, hasText)
            let dxfName = try readText(&main, &text, hasText)
            let zombie = try main.readBit()
            let itemClassID = Int(try main.readBitShort())
            var instances = 0
            if version >= .ac1018 {
                instances = Int(try main.readBitLong())
                _ = try main.readBitLong()  // the DWG version that wrote it
                _ = try main.readBitLong()  // its maintenance version
                _ = try main.readBitLong()
                _ = try main.readBitLong()
            }
            classes[number] = DWGClass(
                number: number, proxyFlags: proxyFlags, applicationName: application,
                cppClassName: cppName, dxfName: dxfName, wasZombie: zombie,
                itemClassID: itemClassID, instanceCount: instances)
        }
        return classes
    }

    private static func readText(_ main: inout BitReader, _ text: inout BitReader, _ separate: Bool)
        throws -> String
    {
        separate ? try text.readVariableText() : try main.readVariableText()
    }
}
