// The object type codes are the format's own, from the Open Design Specification for .dwg files.

/// The fixed object type codes.
///
/// Codes from 500 up are the numbers of a file's own classes.
enum ObjectType {
    static let text = 0x01
    static let attrib = 0x02
    static let attdef = 0x03
    static let block = 0x04
    static let endBlock = 0x05
    static let seqend = 0x06
    static let insert = 0x07
    static let minsert = 0x08
    static let vertex2D = 0x0A
    static let vertex3D = 0x0B
    static let vertexMesh = 0x0C
    static let vertexPFace = 0x0D
    static let vertexPFaceFace = 0x0E
    static let polyline2D = 0x0F
    static let polyline3D = 0x10
    static let arc = 0x11
    static let circle = 0x12
    static let line = 0x13
    static let dimensionOrdinate = 0x14
    static let dimensionLinear = 0x15
    static let dimensionAligned = 0x16
    static let dimensionAngular3Point = 0x17
    static let dimensionAngular2Line = 0x18
    static let dimensionRadius = 0x19
    static let dimensionDiameter = 0x1A
    static let point = 0x1B
    static let face3D = 0x1C
    static let polylinePFace = 0x1D
    static let polylineMesh = 0x1E
    static let solid = 0x1F
    static let trace = 0x20
    static let shape = 0x21
    static let viewport = 0x22
    static let ellipse = 0x23
    static let spline = 0x24
    static let region = 0x25
    static let solid3D = 0x26
    static let body = 0x27
    static let ray = 0x28
    static let xline = 0x29
    static let dictionary = 0x2A
    static let oleFrame = 0x2B
    static let mtext = 0x2C
    static let leader = 0x2D
    static let tolerance = 0x2E
    static let mline = 0x2F
    static let blockControl = 0x30
    static let blockHeader = 0x31
    static let layerControl = 0x32
    static let layer = 0x33
    static let styleControl = 0x34
    static let style = 0x35
    static let lineTypeControl = 0x38
    static let lineType = 0x39
    static let viewControl = 0x3C
    static let view = 0x3D
    static let ucsControl = 0x3E
    static let ucs = 0x3F
    static let viewportControl = 0x40
    static let viewportTable = 0x41
    static let appIDControl = 0x42
    static let appID = 0x43
    static let dimensionStyleControl = 0x44
    static let dimensionStyle = 0x45
    static let viewportEntityControl = 0x46
    static let viewportEntityHeader = 0x47
    static let group = 0x48
    static let mlineStyle = 0x49
    static let ole2Frame = 0x4A
    static let longTransaction = 0x4C
    static let lwpolyline = 0x4D
    static let hatch = 0x4E
    static let xrecord = 0x4F
    static let placeholder = 0x50
    static let vbaProject = 0x51
    static let layout = 0x52

    /// The first code that is a class number and not a fixed type.
    static let firstClass = 500
}
