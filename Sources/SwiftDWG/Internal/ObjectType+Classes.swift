// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readUnlistedType, which reads an object of a class by the class's DXF name). See NOTICE.md.

extension ObjectType {
    /// The fixed code that an object of a class is read as, or `type` itself.
    ///
    /// In an R14 file lightweight polylines and hatches have no fixed codes: the file defines a
    /// class for each, and their objects carry its number. Their data is laid out as in the
    /// releases that give them the codes 0x4D and 0x4E, so they are read with the same decoders.
    static func fixedCode(of type: Int, classes: [Int: DWGClass]) -> Int {
        guard type >= firstClass, let found = classes[type] else { return type }
        switch found.dxfName {
        case "LWPOLYLINE", "LWPLINE": return lwpolyline
        case "HATCH": return hatch
        default: return type
        }
    }
}
