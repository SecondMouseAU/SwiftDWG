import Foundation

/// The objects of a DWG, found by handle.
///
/// It holds the pieces every object read needs: the objects section, the map from handle to
/// place, the file's classes, and the text encoding. Objects are decoded when asked for.
struct ObjectStore {
    let container: Container
    let classes: [Int: DWGClass]
    /// The offset of each object in `objects`, by handle.
    let map: [UInt64: Int]
    let objects: [UInt8]
    let textEncoding: String.Encoding

    init(_ container: Container) throws {
        self.container = container
        textEncoding = CodePage.encoding(for: container.codePage) ?? .windowsCP1252
        guard let handles = try container.section("AcDb:Handles"),
            let objects = try container.section("AcDb:AcDbObjects"),
            let classes = try container.section("AcDb:Classes")
        else { throw DWG.Error.invalid("the file has no objects, handles or classes section") }
        self.objects = objects
        map = try ObjectMapReader.read(handles, version: container.version)
        self.classes = try ClassesReader.read(
            classes, version: container.version, maintenanceVersion: container.maintenanceVersion,
            textEncoding: textEncoding)
    }

    /// A store over these pieces, so that a test can damage some of them.
    init(
        container: Container, classes: [Int: DWGClass], map: [UInt64: Int], objects: [UInt8],
        textEncoding: String.Encoding
    ) {
        self.container = container
        self.classes = classes
        self.map = map
        self.objects = objects
        self.textEncoding = textEncoding
    }

    /// Every handle in the file, in order.
    var handles: [UInt64] { map.keys.sorted() }

    /// A reader on the object with this handle, positioned after its type code, or `nil` if the
    /// file has no such object.
    func reader(for handle: UInt64) throws -> ObjectReader? {
        guard let offset = map[handle] else { return nil }
        return try ObjectReader(
            objects: objects, offset: offset, version: container.version, textEncoding: textEncoding
        )
    }

    /// The entity with this handle, or `nil` if there is none or its type is not decoded yet.
    func entity(_ handle: UInt64) throws -> DecodedEntity? {
        guard var reader = try reader(for: handle) else { return nil }
        return try reader.readEntity()
    }

    /// The table record, control object, dictionary or layout with this handle, or `nil` if there
    /// is none or its type is not one of those.
    func tableRecord(_ handle: UInt64) throws -> TableRecord? {
        guard var reader = try reader(for: handle) else { return nil }
        return try reader.readTableRecord()
    }
}
