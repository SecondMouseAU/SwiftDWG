import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

extension SyntheticEntities {
    struct Attribute {
        var text = Text()
        var isDefinition = false
        var tag = "PART_NO"
        var prompt = "Enter the part number:"
        var flags: UInt8 = 5
        var fieldLength: Int16 = 0
        var isLocked = true
        /// The version byte R2010 and later have, and the one an ATTDEF repeats before its prompt.
        var version: UInt8 = 3
        var repeatedVersion: UInt8 = 9
        /// The attribute type R2018 has: 1, 2 or 4.
        var type: UInt8 = 1
        var multiLine = MText()
        var annotationData: [UInt8] = []
        /// The size the object states for its annotation data, when it is not the bytes' count.
        var annotationSize: Int16?
    }

    /// An ATTRIB or ATTDEF laid out as the release writes it, from the field order of the format.
    static func attribute(_ spec: Attribute, version: DWG.Version) -> SyntheticObject {
        var object = SyntheticObject(
            version: version, type: spec.isDefinition ? ObjectType.attdef : ObjectType.attrib,
            entityMode: spec.isDefinition ? 2 : 0, owner: 0x700)
        writeTextFields(spec.text, into: &object)
        if version >= .ac1024 { object.main.byte(spec.version) }
        if version >= .ac1032 {
            object.main.byte(spec.type)
            if spec.type == 2 || spec.type == 4 { writeEmbeddedText(spec, into: &object) }
        }
        object.string(spec.tag)
        object.main.bitShort(spec.fieldLength)
        object.main.byte(spec.flags)
        if version >= .ac1021 { object.main.bit(spec.isLocked) }
        if spec.isDefinition {
            if version >= .ac1024 { object.main.byte(spec.repeatedVersion) }
            object.string(spec.prompt)
        }
        return object
    }

    /// The MTEXT of a multi-line attribute: an entity without its handle, from the entity mode.
    private static func writeEmbeddedText(_ spec: Attribute, into object: inout SyntheticObject) {
        object.main.bits(0, 2)  // an owner is named
        object.handles.handle(0x77)
        object.main.bitLong(0)  // no reactors
        object.main.bit(true)  // no extension dictionary
        object.main.bit(false)  // no binary data
        object.main.bitShort(0)  // colour
        object.main.bitDouble(1.0)  // line type scale
        object.handles.handle(0x10)  // layer
        object.main.bits(0, 2)  // line type by layer
        object.main.bits(0, 2)  // no material
        object.main.byte(0)  // shadow flags
        object.main.bits(0, 2)  // no plot style
        object.main.bits(0, 3)  // no visual styles
        object.main.bitShort(0)  // visible
        object.main.byte(0)  // line weight
        writeMTextFields(spec.multiLine, into: &object)

        object.main.bitShort(spec.annotationSize ?? Int16(spec.annotationData.count))
        if !spec.annotationData.isEmpty {
            for byte in spec.annotationData { object.main.byte(byte) }
            object.handles.handle(0x66)  // the application
            object.main.bitShort(0)
        }
    }
}

@Suite("ATTRIB and ATTDEF from constructed objects")
struct SyntheticAttributeTests {
    static let versions: [DWG.Version] = [
        .ac1014, .ac1015, .ac1018, .ac1021, .ac1024, .ac1027, .ac1032,
    ]

    private static func read(_ spec: SyntheticEntities.Attribute, _ version: DWG.Version) throws
        -> (common: EntityCommon, data: AttributeData)?
    {
        var reader = try SyntheticEntities.attribute(spec, version: version).reader()
        guard let decoded = try reader.readEntity(), case .attribute(let data) = decoded.geometry
        else { return nil }
        return (decoded.common, data)
    }

    @Test("an ATTRIB reads its text, tag, flags and lock in every release")
    func attrib() throws {
        let spec = SyntheticEntities.Attribute()
        for version in Self.versions {
            guard let (common, data) = try Self.read(spec, version) else {
                Issue.record("\(version) did not read an ATTRIB")
                continue
            }
            #expect(!data.isDefinition, "\(version)")
            #expect(common.entityMode == 0 && common.owner == 0x700, "\(version)")
            #expect(data.text.insertion == DXF.Point(10, 20, 2.5), "\(version)")
            #expect(data.text.height == 3 && data.text.value == "Hi there", "\(version)")
            #expect(data.text.style == 0x31, "\(version)")
            #expect(data.tag == "PART_NO" && data.flags == 5, "\(version)")
            #expect(data.prompt.isEmpty, "\(version)")
            #expect(data.isPositionLocked == (version >= .ac1021), "\(version)")
            #expect(data.version == (version >= .ac1024 ? 3 : 0), "\(version)")
            #expect(data.type == 1 && data.multiLineText == nil, "\(version)")
        }
    }

    @Test("an ATTDEF reads its prompt, and keeps the first of its two version bytes")
    func attdef() throws {
        var spec = SyntheticEntities.Attribute()
        spec.isDefinition = true
        spec.fieldLength = 12
        spec.isLocked = false
        for version in Self.versions {
            guard let (common, data) = try Self.read(spec, version) else {
                Issue.record("\(version) did not read an ATTDEF")
                continue
            }
            #expect(data.isDefinition, "\(version)")
            #expect(common.entityMode == 2, "\(version)")
            #expect(data.tag == "PART_NO" && data.prompt == "Enter the part number:", "\(version)")
            #expect(data.flags == 5 && data.fieldLength == 12, "\(version)")
            #expect(!data.isPositionLocked, "\(version)")
            #expect(data.version == (version >= .ac1024 ? 3 : 0), "\(version)")
        }
    }

    @Test("the fields a TEXT leaves out by default are left out of an attribute too")
    func defaults() throws {
        var spec = SyntheticEntities.Attribute()
        spec.text.flags = 0xFF
        spec.text.thickness = 0
        for version in Self.versions where version >= .ac1015 {
            guard let (_, data) = try Self.read(spec, version) else {
                Issue.record("\(version) did not read an ATTRIB")
                continue
            }
            #expect(data.text.alignmentPoint == nil, "\(version)")
            #expect(data.text.rotation == 0 && data.text.widthFactor == 1, "\(version)")
            #expect(data.tag == "PART_NO" && data.flags == 5, "\(version)")
        }
    }

    @Test("R2018 keeps the text of a multi-line attribute, whatever follows it")
    func multiLine() throws {
        for isDefinition in [false, true] {
            for (type, annotation) in [(UInt8(2), [UInt8]()), (4, []), (2, [1, 2, 3])] {
                var spec = SyntheticEntities.Attribute()
                spec.isDefinition = isDefinition
                spec.type = type
                spec.annotationData = annotation
                let label = "type \(type), \(annotation.count) annotation bytes, \(isDefinition)"
                guard let (_, data) = try Self.read(spec, .ac1032) else {
                    Issue.record("\(label) was not read")
                    continue
                }
                #expect(data.type == Int(type), "\(label)")
                let text = try #require(data.multiLineText, "\(label)")
                #expect(text.value == "one\\Ptwo" && text.height == 2.5, "\(label)")
                #expect(text.attachment == 5 && text.drawingDirection == 3, "\(label)")
                #expect(text.rectangleWidth == 40.5 && text.rectangleHeight == 7.5, "\(label)")
                #expect(text.style == 0x31, "\(label)")
                // What comes after the embedded text is read from the right place.
                #expect(data.tag == "PART_NO" && data.flags == 5, "\(label)")
                #expect(data.isPositionLocked, "\(label)")
                #expect(data.prompt == (isDefinition ? "Enter the part number:" : ""), "\(label)")
            }
        }
    }

    @Test("R2018 reads a single-line attribute, and a type it does not know, without MTEXT")
    func singleLine() throws {
        for type in [UInt8(0), 1, 3, 8] {
            var spec = SyntheticEntities.Attribute()
            spec.type = type
            guard let (_, data) = try Self.read(spec, .ac1032) else {
                Issue.record("type \(type) was not read")
                continue
            }
            #expect(data.type == Int(type) && data.multiLineText == nil, "type \(type)")
            #expect(data.tag == "PART_NO" && data.flags == 5, "type \(type)")
        }
    }

    @Test("annotation data that is longer than the object is refused, not read past")
    func hugeAnnotation() throws {
        var spec = SyntheticEntities.Attribute()
        spec.type = 2
        spec.annotationData = [1, 2, 3]
        spec.annotationSize = 32000
        var reader = try SyntheticEntities.attribute(spec, version: .ac1032).reader()
        #expect(throws: DWG.Error.self) { _ = try reader.readEntity() }
    }

    @Test("a hand-made attribute cut anywhere throws or reads, and does not trap")
    func truncation() throws {
        for version in Self.versions {
            for isDefinition in [false, true] {
                var spec = SyntheticEntities.Attribute()
                spec.isDefinition = isDefinition
                if version >= .ac1032 {
                    spec.type = 2
                    spec.annotationData = [1, 2, 3]
                }
                let whole = SyntheticEntities.attribute(spec, version: version).bytes()
                for length in 0..<whole.count {
                    var reader = try? ObjectReader(
                        objects: Array(whole.prefix(length)), offset: 0, version: version,
                        textEncoding: .windowsCP1252)
                    _ = try? reader?.readEntity()
                }
            }
        }
    }

    @Test("ATTRIB and ATTDEF are decoded types, so a failure to read one is counted by name")
    func names() {
        #expect(ObjectType.decodedTypeName(ObjectType.attrib) == "ATTRIB")
        #expect(ObjectType.decodedTypeName(ObjectType.attdef) == "ATTDEF")
        #expect(ObjectType.typeName(ObjectType.attrib, classes: [:]) == nil)
        #expect(ObjectType.typeName(ObjectType.attdef, classes: [:]) == nil)
        #expect(ObjectType.isEntity(ObjectType.attrib, classes: [:]))
        #expect(ObjectType.isEntity(ObjectType.attdef, classes: [:]))
    }
}
