extension DWG {
    /// What a type name in `DXF.Drawing.skipped` stands for, when this reader wrote it.
    ///
    /// The DXF text that ``DWG/read(contentsOf:options:)`` hands to SwiftDXF holds, for everything
    /// the reader leaves out, a marker record named with one of two prefixes. SwiftDXF tallies it
    /// in `skipped` and `skippedByLayer` under that name, like any record it does not model. The
    /// prefixes keep three different reasons for a gap apart:
    ///
    /// - ``notDecoded(type:)``: the entity is of a type this reader does not decode yet, such as a
    ///   `VIEWPORT`, an `IMAGE` or a `3DSOLID`. The file is fine and its content did not reach the
    ///   drawing. It is not a record of that type, so SwiftDXF cannot take it for one it models.
    /// - ``unreadable(type:)``, ``unreadableObject`` and ``unreadableTableRecord(_:)``: the file is
    ///   damaged, and what it held could not be read.
    /// - A name with neither prefix, which ``init(typeName:)`` answers `nil` for, is a record the
    ///   reader wrote as itself and SwiftDXF does not model, such as an `INSERT` it kept as a
    ///   block reference.
    ///
    /// The names are made and taken apart only here, so a consumer that classifies a key of
    /// `skipped` with ``init(typeName:)`` follows whatever the reader writes.
    ///
    /// An entity's marker carries its layer (group 8) when the file's layer handle for it could be
    /// read and the layer itself was, so `skippedByLayer` counts it under the layer it is on. An
    /// entity whose layer could not be resolved, an object that could not be opened, and a table
    /// record have no layer, and SwiftDXF counts them on layer `0`.
    public enum SkippedKind: Hashable, Sendable {
        /// The tables whose records can be lost, named as DXF names the table.
        public enum Table: String, CaseIterable, Sendable {
            case layer = "LAYER"
            case lineType = "LTYPE"
            case textStyle = "STYLE"
            case dimensionStyle = "DIMSTYLE"
            /// The record of a block, which a block that cannot be read is lost with.
            case blockRecord = "BLOCK_RECORD"
        }

        /// An entity of this DXF type that this reader does not decode.
        case notDecoded(type: String)
        /// An entity of this DXF type that is in the file and could not be read, or a polyline
        /// with a vertex that could not be read (`POLYLINE`).
        case unreadable(type: String)
        /// An object that could not be opened, or that the file does not hold, so has no type to
        /// name.
        case unreadableObject
        /// A record of a symbol table, or a block, that could not be read.
        case unreadableTableRecord(Table)

        /// The type name SwiftDXF tallies it under: the name of the marker record the reader
        /// writes.
        public var typeName: String {
            switch self {
            case .notDecoded(let type): return DWG.notDecodedPrefix + type
            case .unreadable(let type): return DWG.unreadablePrefix + type
            case .unreadableObject: return DWG.unreadablePrefix + Self.objectName
            case .unreadableTableRecord(let table): return DWG.unreadablePrefix + table.rawValue
            }
        }

        /// What a type name from `DXF.Drawing.skipped` or `skippedByLayer` stands for, or `nil`
        /// when it is not one of the reader's markers.
        public init?(typeName: String) {
            if let type = Self.remainder(of: typeName, after: DWG.notDecodedPrefix) {
                self = .notDecoded(type: type)
            } else if let type = Self.remainder(of: typeName, after: DWG.unreadablePrefix) {
                if type == Self.objectName {
                    self = .unreadableObject
                } else if let table = Table(rawValue: type) {
                    self = .unreadableTableRecord(table)
                } else {
                    self = .unreadable(type: type)
                }
            } else {
                return nil
            }
        }

        /// What follows `prefix` in `name`, if it starts with it and something follows.
        private static func remainder(of name: String, after prefix: String) -> String? {
            guard name.hasPrefix(prefix), name.count > prefix.count else { return nil }
            return String(name.dropFirst(prefix.count))
        }

        /// What an object that has no type is called after the prefix.
        private static let objectName = "OBJECT"

        /// Whether the file is damaged where this was left out, as opposed to a type that is not
        /// decoded.
        public var isUnreadable: Bool {
            if case .notDecoded = self { return false }
            return true
        }
    }

    /// What `DXF.Drawing.skipped` holds before the type of something that is in the file and could
    /// not be read: `UNREADABLE_LINE`, `UNREADABLE_OBJECT`, `UNREADABLE_LAYER`.
    ///
    /// It means the file is damaged. See ``SkippedKind``.
    public static let unreadablePrefix = "UNREADABLE_"

    /// What `DXF.Drawing.skipped` holds before the type of an entity that this reader does not
    /// decode: `NOT_DECODED_VIEWPORT`, `NOT_DECODED_3DSOLID`.
    ///
    /// It does not mean the file is damaged, and it is not that the drawing model leaves the type
    /// out: the reader did not turn the entity into a record SwiftDXF could read. See
    /// ``SkippedKind``.
    public static let notDecodedPrefix = "NOT_DECODED_"

    /// The tables whose records are counted under ``unreadablePrefix`` when one cannot be read:
    /// `LAYER`, `LTYPE`, `STYLE`, `DIMSTYLE` and `BLOCK_RECORD`.
    public static var unreadableTableTypes: [String] {
        SkippedKind.Table.allCases.map(\.rawValue)
    }
}
