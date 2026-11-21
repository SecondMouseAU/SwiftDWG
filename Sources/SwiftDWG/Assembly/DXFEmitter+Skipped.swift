import Foundation

extension DXFEmitter {
    /// Writes the marker for something that is in the file and is not written as a record of its
    /// own type, so that SwiftDXF tallies it among the entities it skips.
    ///
    /// The marker's name comes from `DWG.SkippedKind`, which is also what a consumer classifies
    /// the tally with, so the two cannot differ. It carries the handle, the paper space flag, and
    /// the layer when `layer` is the handle of one the document holds. A marker never has the
    /// name of a type SwiftDXF models: it would be read as an entity with nothing in it.
    mutating func writeSkipped(
        _ kind: DWG.SkippedKind, handle: UInt64, space: Space, layer: UInt64 = 0
    ) {
        writer.begin(kind.typeName)
        writer.handle(5, handle)
        if space == .paper { writer.group(67, 1) }
        if let name = document.layerNames[layer] { writer.group(8, name) }
    }

    /// Counts an entity that was not written as a record of its type.
    ///
    /// An entity of a type this reader does not decode is counted as `notDecoded`; one that is of
    /// a type it decodes, and failed (`unreadable`), as `unreadable`. Either way it is counted on
    /// its layer, read from the common data that every entity starts with, without decoding the
    /// rest of it. If that cannot be read as far as the layer, it has none.
    ///
    /// An object that cannot be opened at all, that the file does not hold, or whose type is not
    /// one this reader knows as an entity, has no type to name, and is counted as
    /// `unreadableObject`. The types that are not decoded are the ones
    /// `ObjectType.typeName(_:classes:)` names: a type moves from there to
    /// `ObjectType.decodedTypeName(_:)` when a decoder is written for it, and is then no longer
    /// counted here.
    mutating func writeUndecoded(
        _ handle: UInt64, space: Space, unreadable: Bool = false
    ) {
        let opened: ObjectReader?
        do {
            opened = try store.reader(for: handle)
        } catch {
            opened = nil
        }
        guard var reader = opened else {
            writeSkipped(.unreadableObject, handle: handle, space: space)
            return
        }
        // A type this reader decodes has a name only in the other list: it comes here only if
        // it failed to decode.
        let name =
            ObjectType.typeName(reader.type, classes: store.classes)
            ?? (unreadable ? ObjectType.decodedTypeName(reader.type) : nil)
        guard let name else {
            // Not a type this reader knows as an entity: it is still counted, by what it is not.
            writeSkipped(.unreadableObject, handle: handle, space: space)
            return
        }

        var common = EntityCommon()
        _ = try? reader.readEntityCommon(into: &common)
        writeSkipped(
            unreadable ? .unreadable(type: name) : .notDecoded(type: name),
            handle: handle, space: space, layer: common.layer)
    }

    /// Table records and blocks that could not be read, so that SwiftDXF counts them.
    mutating func writeLostRecords() {
        for lost in document.lostRecords {
            writeSkipped(.unreadableTableRecord(lost.table), handle: lost.handle, space: .model)
        }
    }
}
