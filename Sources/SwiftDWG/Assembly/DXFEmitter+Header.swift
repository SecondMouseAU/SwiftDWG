import SwiftDXF

extension DXFEmitter {
    /// Writes the HEADER section: every variable the release stores that AutoCAD's DXF has, in the
    /// order and with the group codes `HeaderLayout` lists.
    ///
    /// The values are the ones the file holds. A variable DXF writes as the name of an object, such
    /// as `$CLAYER`, is written with the name of the object the file's handle points at.
    mutating func writeHeader() {
        var header = document.header
        header.values["$ACADVER"] = .string(document.version.code)
        if let page = CodePage.dxfName(for: store.container.codePage) {
            header.values["$DWGCODEPAGE"] = .string(page)
        }
        writer.beginSection("HEADER")
        for entry in HeaderLayout.entries {
            write(entry, from: header)
        }
        writer.endSection()
    }

    private mutating func write(_ entry: HeaderLayout.Entry, from header: HeaderVariables) {
        let name = entry.name
        guard let value = header.values[name] else { return }
        switch entry.kind {
        case .integer(let code):
            guard let number = header.int(name) else { return }
            begin(name)
            writer.group(code, number)
        case .real(let code):
            guard let number = header.double(name) else { return }
            begin(name)
            writer.group(code, number)
        case .text(let code):
            guard let text = header.string(name) else { return }
            begin(name)
            writer.group(code, text)
        case .point2:
            guard let point = header.point2(name) else { return }
            begin(name)
            writer.point2D(10, x: point.x, y: point.y)
        case .point3:
            guard let point = header.point3(name) else { return }
            begin(name)
            writer.point(10, DXF.Point(point.x, point.y, point.z))
        case .color(let code):
            guard case .color(let index, let rgb) = value else { return }
            begin(name)
            writer.group(code, Self.paletteIndex(index: index, rgb: rgb))
        case .name(let code, let table):
            guard let text = headerName(value, in: table, emptyWhenNull: false) else { return }
            begin(name)
            writer.group(code, text)
        case .nameOrEmpty(let code, let table):
            guard let text = headerName(value, in: table, emptyWhenNull: true) else { return }
            begin(name)
            writer.group(code, text)
        case .handle(let code):
            // A null handle is a variable that points at nothing, which AutoCAD does not write.
            guard case .handle(let handle) = value, handle != 0 else { return }
            begin(name)
            writer.handle(code, handle)
        case .clipFrame:
            guard let number = header.int(name) else { return }
            begin(name)
            if document.version >= .ac1024 {
                writer.group(280, number)
            } else {
                // Before R2010 the variable could be 0 or 1. AutoCAD's own DXF of an R2004 and an
                // R2007 drawing has 0 where the DWG has 2, which is a value of a later release.
                writer.group(290, number > 1 ? 0 : number)
            }
        }
    }

    private mutating func begin(_ name: String) {
        writer.group(9, name)
    }

    /// The palette index a colour is written as: the index itself, or the one nearest to a true
    /// colour, since DXF's header has no place for the colour.
    private static func paletteIndex(index: Int, rgb: UInt32?) -> Int {
        guard let rgb else { return index }
        return ColorIndex.nearest(
            red: UInt8(rgb >> 16 & 0xFF), green: UInt8(rgb >> 8 & 0xFF), blue: UInt8(rgb & 0xFF))
    }

    // MARK: Names

    /// The text of a variable that DXF writes as a name.
    ///
    /// R13 and R14 keep a few of them as text, written as they are. From R2000 they are handles,
    /// and a handle becomes the name of its object. A null handle is an empty name when the
    /// variable may be unset, and no name otherwise, as is a handle that names nothing the
    /// document holds.
    private func headerName(
        _ value: HeaderVariables.Value, in table: HeaderLayout.Table, emptyWhenNull: Bool
    ) -> String? {
        if case .string(let text) = value { return text }
        guard case .handle(let handle) = value else { return nil }
        if handle == 0 { return emptyWhenNull ? "" : nil }
        switch table {
        case .layer: return document.layerNames[handle]
        case .textStyle: return document.textStyleNames[handle]
        case .lineType: return document.lineTypeNames[handle]
        case .dimensionStyle: return document.dimensionStyleNames[handle]
        case .block: return document.blockNames[handle].map(Self.arrowheadName)
        case .ucs: return store.userCoordinateSystemName(handle)
        case .mlineStyle:
            let dictionary = document.header.handles["DICTIONARY_ACAD_MLINESTYLE"] ?? 0
            return store.multilineStyleName(handle, dictionary: dictionary)
        }
    }

    /// The names of the blocks AutoCAD draws its own arrowheads with, in capitals.
    private static let builtInArrowheads: Set<String> = [
        "_ARCHTICK", "_BOXBLANK", "_BOXFILLED", "_CLOSED", "_CLOSEDBLANK", "_DATUMBLANK",
        "_DATUMFILLED", "_DOT", "_DOTBLANK", "_DOTSMALL", "_INTEGRAL", "_NONE", "_OBLIQUE", "_OPEN",
        "_OPEN30", "_OPEN90", "_ORIGIN", "_ORIGIN2", "_SMALL",
    ]

    /// The name DXF's header gives an arrowhead block.
    ///
    /// The block of one of AutoCAD's own arrowheads is named with an underscore (`_BoxBlank`) and
    /// the header without (`BoxBlank`). A block of the user's own keeps its name.
    static func arrowheadName(_ block: String) -> String {
        builtInArrowheads.contains(block.uppercased()) ? String(block.dropFirst()) : block
    }
}
