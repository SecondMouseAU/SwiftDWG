import Foundation
import SwiftDXF

extension DWG {
    /// Reads a DWG file into SwiftDXF's drawing model.
    ///
    /// The result is the drawing that SwiftDXF would give for AutoCAD's DXF export of the same
    /// file: its entities with their handles as identities, the blocks, the layer, line type and
    /// dimension style tables, the units and the extents.
    ///
    /// Nothing the reader leaves out is dropped without a count. SwiftDXF tallies each in the
    /// drawing's `skipped`, and by layer in `skippedByLayer` (for an entity in a block, in the
    /// block's own), under a name that says why, which ``DWG/SkippedKind`` classifies:
    ///
    /// - An entity of a type this reader does not decode, such as a `VIEWPORT`, an `IMAGE` or a
    ///   `3DSOLID`, as `NOT_DECODED_` and its type (``DWG/notDecodedPrefix``). The file is fine.
    ///   It is not written as a record of its own type, which SwiftDXF would read as an entity with
    ///   nothing in it if it models the type.
    /// - An entity that cannot be read, as `UNREADABLE_` and its type
    ///   (``DWG/unreadablePrefix``), or `UNREADABLE_OBJECT` when it has none. So is a 2D or 3D
    ///   polyline with a vertex that cannot be read, as `UNREADABLE_POLYLINE`, and a table record
    ///   or a block, under ``DWG/unreadableTableTypes``: `LAYER`, `LTYPE`, `STYLE`, `DIMSTYLE` or
    ///   `BLOCK_RECORD`.
    ///
    /// An entity is counted on its own layer, as it is for a DXF, when the layer can be read from
    /// the entity's common data: the entity's type does not matter, and it is not decoded further.
    /// One whose layer cannot be read, whose object cannot be opened, or that is a table record
    /// has none, and SwiftDXF counts it on layer `0`.
    ///
    /// - Parameters:
    ///   - url: The file to read.
    ///   - options: What SwiftDXF should do with block references and paper space.
    /// - Returns: The drawing.
    /// - Throws: ``DWG/Error`` when the file is not a DWG, is of a release that is not read, or
    ///   is damaged in its structure, which includes a control object of the layer, line type,
    ///   text style, dimension style or block table that cannot be read.
    public static func read(
        contentsOf url: URL, options: DXF.ReadOptions = .init()
    ) throws -> DXF.Drawing {
        try read(data: try Data(contentsOf: url), options: options)
    }

    /// Reads a DWG from its bytes; see ``read(contentsOf:options:)``.
    public static func read(data: Data, options: DXF.ReadOptions = .init()) throws -> DXF.Drawing {
        try DXF.read(text: try dxfText(data: data), options: options)
    }

    /// The DXF text a DWG is read from.
    ///
    /// This is what ``read(data:options:)`` hands to SwiftDXF. It is public so that a reading can
    /// be inspected, or saved as a DXF.
    public static func dxfText(data: Data) throws -> String {
        var emitter = DXFEmitter(try Document([UInt8](data)))
        return emitter.text()
    }
}
