import Foundation
import SwiftDXF

extension DWG {
    /// Reads a DWG file into SwiftDXF's drawing model.
    ///
    /// The result is the drawing that SwiftDXF would give for AutoCAD's DXF export of the same
    /// file: its entities with their handles as identities, the blocks, the layer, line type and
    /// dimension style tables, the units and the extents.
    ///
    /// - Parameters:
    ///   - url: The file to read.
    ///   - options: What SwiftDXF should do with block references and paper space.
    /// - Returns: The drawing.
    /// - Throws: ``DWG/Error`` when the file is not a DWG, is of a release that is not read, or
    ///   is damaged in its structure. An entity that cannot be read is left out and counted in
    ///   `skipped`, under its type name with `UNREADABLE_` before it.
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
