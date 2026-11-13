// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (the object framework: getEntityType, updateHandleReader, readCommonData, readExtendedData,
// readCommonEntityData, readEntityMode and the common non-entity data). See NOTICE.md. The layout
// is the format's own, from the Open Design Specification for .dwg files.

import Foundation

/// Thrown by a decoder that has not been written yet, so a caller can skip that type.
struct NotDecodedYet: Error {
    let what: String
}

/// One object cut out of the `AcDb:AcDbObjects` section, with the streams its fields are in.
///
/// An object keeps its numbers, its text and its handle references in three runs of bits: the
/// main data, the strings (from R2007, in a stream of their own), and the handles at the end.
/// This holds a reader on each and reads the data every object starts with.
struct ObjectReader {
    let version: DWG.Version
    /// The numbers and flags.
    var main: BitReader
    /// The handle references.
    var handles: BitReader
    /// The strings, when the file keeps them apart (R2007 and later).
    private var text: BitReader
    private var hasTextStream = false
    /// Where the object's data starts, which the offsets inside it count from.
    let initialBit: Int
    /// The object's type code.
    let type: Int
    /// The object's own handle, once `readCommonData` has read it.
    private(set) var handle: UInt64 = 0

    /// Starts reading the object at `offset` in the objects section.
    init(
        objects: [UInt8], offset: Int, version: DWG.Version, textEncoding: String.Encoding
    ) throws {
        self.version = version
        guard offset >= 0, offset < objects.count else {
            throw DWG.Error.invalid("object offset \(offset) is outside the objects section")
        }
        var head = BitReader(objects, version: version, position: offset * 8)
        head.textEncoding = textEncoding

        // The size of the object in bytes, not counting its CRC.
        let size = try head.readModularShort()
        guard size > 0 else { throw DWG.Error.invalid("object of size \(size)") }

        main = head
        handles = head
        text = head
        if version >= .ac1024 {
            // The size in bits of the handle stream, which is the end of the object.
            let handleSize = Int(try head.readModularChar())
            let handleStart = head.position + size * 8 - handleSize
            guard handleSize >= 0, handleStart >= head.position, handleStart <= head.bitCount else {
                throw DWG.Error.invalid("object handle stream of \(handleSize) bits")
            }
            main = head
            initialBit = head.position
            type = try main.readObjectType()
            try handles.seek(toBit: handleStart)
            if let start = try head.stringStreamStart(flagBit: handleStart - 1) {
                try text.seek(toBit: start)
                hasTextStream = true
            }
        } else {
            initialBit = head.position
            type = try main.readObjectType()
        }
    }

    /// Reads a string from where this release keeps it.
    mutating func readText() throws -> String {
        if version >= .ac1021 {
            return hasTextStream ? try text.readVariableText() : ""
        }
        return try main.readVariableText()
    }

    /// Reads a handle reference from the handle stream.
    mutating func readHandle(relativeTo reference: UInt64 = 0) throws -> UInt64 {
        try handles.readHandle(relativeTo: reference)
    }

    /// Reads a reference to another object, relative to this object's own handle.
    mutating func readOwnHandle() throws -> UInt64 {
        try handles.readHandle(relativeTo: handle)
    }

    /// Moves the handle stream to where the object's data says it starts.
    ///
    /// From R2000 to R2007 that is given by a long read just after the object's data begins.
    /// R2007 also puts its strings in front of that point.
    mutating func updateHandleReader() throws {
        let size = Int(try main.readRawLong())
        guard size >= 0 else { throw DWG.Error.invalid("object data size \(size)") }
        try handles.seek(toBit: size + initialBit)
        if version == .ac1021 {
            text = main
            if let start = try main.stringStreamStart(flagBit: size + initialBit - 1) {
                try text.seek(toBit: start)
                hasTextStream = true
            } else {
                hasTextStream = false
            }
        }
    }

    // MARK: What every object starts with

    /// A block of data a program attached to an object, kept as the bytes it was stored in.
    struct ExtendedData {
        /// The handle of the application that owns it.
        var application: UInt64
        var bytes: [UInt8]
    }

    /// Reads the handle and the extended data that follow the object type.
    mutating func readCommonData() throws -> [ExtendedData] {
        if version >= .ac1015 && version < .ac1024 { try updateHandleReader() }
        handle = try main.readHandle()
        var records: [ExtendedData] = []
        var size = Int(try main.readBitShort())
        while size != 0 {
            guard size > 0, records.count < 1024 else {
                throw DWG.Error.invalid("extended data size \(size)")
            }
            let application = try main.readHandle()
            records.append(ExtendedData(application: application, bytes: try main.readBytes(size)))
            size = Int(try main.readBitShort())
        }
        return records
    }

    /// What every object that is not an entity has after its common data: its owner, its
    /// reactors and its extension dictionary.
    struct ObjectCommon {
        var handle: UInt64 = 0
        var extendedData: [ExtendedData] = []
        var owner: UInt64 = 0
        var reactors: [UInt64] = []
        var extensionDictionary: UInt64 = 0
    }

    /// Reads the common data of an object that is not an entity (a table entry, a dictionary).
    mutating func readObjectCommon() throws -> ObjectCommon {
        var common = ObjectCommon()
        common.extendedData = try readCommonData()
        common.handle = handle
        if version <= .ac1014 { try updateHandleReader() }
        common.owner = try readOwnHandle()
        try readReactors(into: &common.reactors, dictionary: &common.extensionDictionary)
        return common
    }

    /// Reads the reactor handles and the extension dictionary handle.
    mutating func readReactors(into reactors: inout [UInt64], dictionary: inout UInt64) throws {
        let count = Int(try main.readBitLong())
        guard count >= 0, count < 1 << 20 else { throw DWG.Error.invalid("\(count) reactors") }
        for _ in 0..<count { reactors.append(try readHandle()) }
        var missing = false
        if version >= .ac1018 { missing = try main.readBit() }
        if !missing { dictionary = try readHandle() }
        // R2013 and later: a bit for binary data held in the data store.
        if version >= .ac1027 { _ = try main.readBit() }
    }
}
