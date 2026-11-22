import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// How the reader counts what it leaves out: the names it uses, and the layer a counted entity is
/// on.
///
/// The names are checked without a file. The layers are checked on objects built by hand, which
/// reach the releases and the failures no drawing does, and against AutoCAD's own DXF export of
/// the sample drawings, which holds entities of types that SwiftDWG does not decode, on layers
/// other than `0`.
///
/// The checks through `DWG.read` and `skippedByLayer` were run under SwiftDXF 0.4.0 and under
/// 0.6.0 and hold under both. 0.6.0 and later model TOLERANCE and WIPEOUT and 0.4.0 skips them,
/// which does not change what is compared: the marker is not named as either type.
@Suite("Skipped records")
struct SkippedRecordTests {
    // MARK: The names

    @Test("each kind has the name the reader writes, and the name gives the kind back")
    func names() {
        let kinds: [(DWG.SkippedKind, String)] = [
            (.notDecoded(type: "VIEWPORT"), "NOT_DECODED_VIEWPORT"),
            (.notDecoded(type: "3DSOLID"), "NOT_DECODED_3DSOLID"),
            (.unreadable(type: "LINE"), "UNREADABLE_LINE"),
            (.unreadable(type: "POLYLINE"), "UNREADABLE_POLYLINE"),
            (.unreadableObject, "UNREADABLE_OBJECT"),
            (.unreadableTableRecord(.layer), "UNREADABLE_LAYER"),
            (.unreadableTableRecord(.lineType), "UNREADABLE_LTYPE"),
            (.unreadableTableRecord(.textStyle), "UNREADABLE_STYLE"),
            (.unreadableTableRecord(.dimensionStyle), "UNREADABLE_DIMSTYLE"),
            (.unreadableTableRecord(.blockRecord), "UNREADABLE_BLOCK_RECORD"),
        ]
        for (kind, name) in kinds {
            #expect(kind.typeName == name)
            #expect(DWG.SkippedKind(typeName: name) == kind, "\(name)")
        }
    }

    @Test("a type name that is not the reader's marker is not classified")
    func ordinaryNames() {
        for name in [
            "INSERT", "VIEWPORT", "TRACE", "MLINE", "UNREADABLE", "NOT_DECODED", "UNREADABLE_",
            "NOT_DECODED_", "not_decoded_VIEWPORT", "XUNREADABLE_LINE", "", " ",
        ] {
            #expect(DWG.SkippedKind(typeName: name) == nil, "\(name)")
        }
    }

    @Test("only a type that is not decoded is not damage")
    func damage() {
        #expect(!DWG.SkippedKind.notDecoded(type: "VIEWPORT").isUnreadable)
        #expect(DWG.SkippedKind.unreadable(type: "VIEWPORT").isUnreadable)
        #expect(DWG.SkippedKind.unreadableObject.isUnreadable)
        #expect(DWG.SkippedKind.unreadableTableRecord(.layer).isUnreadable)
    }

    @Test("the exported prefixes and table names are the ones the markers are made of")
    func exportedNames() {
        #expect(DWG.unreadablePrefix == "UNREADABLE_")
        #expect(DWG.notDecodedPrefix == "NOT_DECODED_")
        #expect(
            DWG.unreadableTableTypes == ["LAYER", "LTYPE", "STYLE", "DIMSTYLE", "BLOCK_RECORD"])
        #expect(!DWG.unreadablePrefix.hasPrefix(DWG.notDecodedPrefix))
        #expect(!DWG.notDecodedPrefix.hasPrefix(DWG.unreadablePrefix))
        for table in DWG.unreadableTableTypes {
            let name = DWG.unreadablePrefix + table
            guard case .unreadableTableRecord(let found)? = DWG.SkippedKind(typeName: name) else {
                Issue.record("\(name) is not a lost table record")
                continue
            }
            #expect(found.rawValue == table)
        }
        // A type that is not a table is an entity, and an object has its own kind.
        #expect(
            DWG.SkippedKind(typeName: "UNREADABLE_LINE") == .unreadable(type: "LINE"))
        #expect(DWG.SkippedKind(typeName: "UNREADABLE_OBJECT") == .unreadableObject)
    }

    // MARK: Objects built by hand

    /// The handle the hand-built object is given in the drawing.
    private static let added: UInt64 = 0x7F00

    /// The layer handle every hand-built object names.
    private static let layerHandle: UInt64 = 0x10

    /// The committed drawing, written as DXF text with this object added to its model space (or
    /// its paper space), where `object` is the object's bytes as `CurveObject` builds them less
    /// the last `dropping`, and with the layer of `layerHandle` named `layer`, or unnamed.
    private static func text(
        adding object: CurveObject, dropping tail: Int = 0, in space: DXFEmitter.Space = .model,
        layer: String? = "Walls"
    ) throws -> String {
        var object = object
        object.handle = added
        let whole = try ObjectStore(try Container(try Fixtures.data("BLOCKPOINTPARAMETER.dwg")))
        var bytes = object.bytes()
        bytes.removeLast(tail)
        var map = whole.map
        map[added] = whole.objects.count
        let store = ObjectStore(
            container: whole.container, classes: whole.classes, map: map,
            objects: whole.objects + bytes, textEncoding: whole.textEncoding)
        var document = try Document(store: store)
        document.layerNames[layerHandle] = layer
        let target = space == .paper ? document.paperSpace : document.modelSpace
        let index = try #require(document.blocks.firstIndex { $0.handle == target })
        document.blocks[index].entities.append(added)
        var emitter = DXFEmitter(document)
        return emitter.text()
    }

    private static func record(in text: String) throws -> DXFRecord {
        try #require(DXFGroups.records(text: text)[added])
    }

    /// An entity of a type that is not decoded, with its common data and nothing else.
    private static func viewport(_ version: DWG.Version = .ac1032) -> CurveObject {
        CurveObject(version, type: ObjectType.viewport)
    }

    @Test("an entity that is not decoded is counted under its layer, in any release")
    func layerInEveryRelease() throws {
        for version in HandBuiltObjectTests.releases {
            var reader = try Self.viewport(version).reader()
            var common = EntityCommon()
            try reader.readEntityCommon(into: &common)
            #expect(common.layer == Self.layerHandle, "\(version)")
            #expect(reader.type == ObjectType.viewport, "\(version)")
        }
    }

    @Test("a marker for an entity that is not decoded carries the layer, and SwiftDXF counts it")
    func notDecodedLayer() throws {
        let text = try Self.text(adding: Self.viewport())
        let marker = try Self.record(in: text)
        #expect(marker.type == "NOT_DECODED_VIEWPORT")
        #expect(marker.first(8) == "Walls")
        #expect(marker.first(67) == nil)

        let drawing = try DXF.read(text: text)
        #expect(drawing.skippedByLayer["NOT_DECODED_VIEWPORT"] == ["Walls": 1])
        #expect(drawing.skipped["NOT_DECODED_VIEWPORT"] == 1)
        // It is not a record of the type, which SwiftDXF would read as one it models or skips as
        // that type.
        #expect(drawing.skipped["VIEWPORT"] == nil)
    }

    @Test("a marker in paper space keeps the paper space flag beside the layer")
    func paperSpace() throws {
        let marker = try Self.record(in: try Self.text(adding: Self.viewport(), in: .paper))
        #expect(marker.type == "NOT_DECODED_VIEWPORT")
        #expect(marker.first(8) == "Walls")
        #expect(marker.first(67) == "1")
    }

    @Test("a layer the document does not hold is not written, and no other one is put in its place")
    func layerNotResolved() throws {
        let text = try Self.text(adding: Self.viewport(), layer: nil)
        let marker = try Self.record(in: text)
        #expect(marker.type == "NOT_DECODED_VIEWPORT")
        #expect(marker.first(8) == nil)
        // SwiftDXF counts a record with no layer on layer 0.
        #expect(try DXF.read(text: text).skippedByLayer["NOT_DECODED_VIEWPORT"] == ["0": 1])
    }

    @Test("an entity whose common data ends before its layer is counted with no layer")
    func layerCut() throws {
        // The object's last bytes are its layer handle and then its CRC.
        let marker = try Self.record(in: try Self.text(adding: Self.viewport(), dropping: 4))
        #expect(marker.type == "NOT_DECODED_VIEWPORT")
        #expect(marker.first(8) == nil)
    }

    @Test("an entity whose common data fails after its layer is counted on the layer it read")
    func layerThenFailure() throws {
        var object = Self.viewport()
        // The line type is by handle and the object has none, so reading it runs out of the file.
        object.lineTypeFlags = 3
        var cut = object.bytes()
        cut.removeLast(2)
        var reader = try ObjectReader(
            objects: cut, offset: 0, version: .ac1032, textEncoding: .windowsCP1252)
        var common = EntityCommon()
        #expect(throws: DWG.Error.self) { try reader.readEntityCommon(into: &common) }
        #expect(common.layer == Self.layerHandle)

        let marker = try Self.record(in: try Self.text(adding: object, dropping: 2))
        #expect(marker.type == "NOT_DECODED_VIEWPORT")
        #expect(marker.first(8) == "Walls")
    }

    @Test("an entity that is decoded and cannot be read is counted by its type, on its layer")
    func unreadableEntity() throws {
        // More points than the object has bits for.
        var object = CurveObject(.ac1032, type: ObjectType.lwpolyline)
        object.main.bitShort(0)
        object.main.bitLong(2_000_000_000)
        let text = try Self.text(adding: object)
        let marker = try Self.record(in: text)
        #expect(marker.type == "UNREADABLE_LWPOLYLINE")
        #expect(marker.first(8) == "Walls")
        #expect(try DXF.read(text: text).skippedByLayer["UNREADABLE_LWPOLYLINE"] == ["Walls": 1])
    }

    @Test("an entity that cannot be read and has no layer to read is counted with none")
    func unreadableEntityNoLayer() throws {
        var object = CurveObject(.ac1032, type: ObjectType.lwpolyline)
        object.main.bitShort(0)
        object.main.bitLong(2_000_000_000)
        let marker = try Self.record(in: try Self.text(adding: object, dropping: 4))
        #expect(marker.type == "UNREADABLE_LWPOLYLINE")
        #expect(marker.first(8) == nil)
    }

    @Test("an object of a type that is no entity is counted as an object with no type")
    func notAnEntity() throws {
        let object = CurveObject(.ac1032, type: ObjectType.xrecord)
        let marker = try Self.record(in: try Self.text(adding: object))
        #expect(marker.type == "UNREADABLE_OBJECT")
        #expect(marker.first(8) == nil)
    }

    @Test("a proxy entity is a healthy entity that is not decoded, and is not counted as damage")
    func proxyEntity() throws {
        let text = try Self.text(adding: CurveObject(.ac1032, type: ObjectType.proxyEntity))
        let marker = try Self.record(in: text)
        #expect(marker.type == "NOT_DECODED_ACAD_PROXY_ENTITY")
        #expect(marker.first(8) == "Walls")
        #expect(DWG.SkippedKind(typeName: marker.type)?.isUnreadable == false)
        // Nothing in a drawing that holds one is damaged.
        let skipped = try DXF.read(text: text).skipped
        #expect(skipped.keys.allSatisfy { DWG.SkippedKind(typeName: $0)?.isUnreadable != true })
    }

    // MARK: Against AutoCAD's DXF

    /// The sample's DWG and AutoCAD's DXF export of the same drawing.
    private static func sample(_ release: String) throws -> (
        data: Data, theirs: URL
    ) {
        let corpus = try #require(Fixtures.corpus)
        let data = try Data(contentsOf: corpus.appendingPathComponent("sample_\(release).dwg"))
        return (data, corpus.appendingPathComponent("sample_\(release)_ascii.dxf"))
    }

    @Test(
        "every entity that is not decoded is on the layer AutoCAD's DXF puts it on",
        .enabled(if: Fixtures.corpus != nil), arguments: DrawingOracleTests.releases)
    func layersAgree(release: String) throws {
        let (data, dxf) = try Self.sample(release)
        let ours = DXFGroups.records(text: try DWG.dxfText(data: data))
        let theirs = try DXFGroups.records(in: dxf)

        var markers = 0
        var layers: [String: Int] = [:]
        for (handle, record) in ours {
            guard case .notDecoded(let type)? = DWG.SkippedKind(typeName: record.type) else {
                continue
            }
            markers += 1
            guard let expected = theirs[handle] else {
                Issue.record("\(release): \(record.type) \(handle) is not in AutoCAD's DXF")
                continue
            }
            // AutoCAD's DXF writes a polyface mesh as a POLYLINE.
            #expect(
                expected.type == (type == "POLYFACE_MESH" ? "POLYLINE" : type),
                "\(release) \(handle)")
            #expect(record.first(8) == expected.first(8), "\(release) \(type) \(handle)")
            layers[expected.first(8) ?? "none", default: 0] += 1
        }
        // The sample holds 37 entities of types SwiftDWG does not decode, 33 on layer 0 and four
        // on three others: a MESH, an ACAD_TABLE and two MLINEs. (It also holds 3 TOLERANCEs, a
        // WIPEOUT and 5 ATTDEFs, on layer 0, which are decoded and so are not among them.)
        #expect(markers == 37, "\(release) \(markers)")
        #expect(layers["0"] == 33 && layers.count == 4, "\(release) \(layers)")
        #expect(
            layers["Layer_true_color"] == 2 && layers["Layer_color_80"] == 1
                && layers["Layer1"] == 1, "\(release) \(layers)")
    }

    @Test(
        "SwiftDXF counts them under the layers it counts AutoCAD's DXF records under",
        .enabled(if: Fixtures.corpus != nil), arguments: DrawingOracleTests.releases)
    func tallyAgrees(release: String) throws {
        let (data, dxf) = try Self.sample(release)
        let ours = try DWG.read(data: data)
        let theirs = try DXF.read(contentsOf: dxf)

        func notDecoded(_ tally: [String: [String: Int]]) -> [String: [String: Int]] {
            var out: [String: [String: Int]] = [:]
            for (name, layers) in tally {
                if case .notDecoded(let type)? = DWG.SkippedKind(typeName: name) {
                    out[type] = layers
                }
            }
            return out
        }
        // Types SwiftDXF models, or reads as another type, have no tally of that name in its
        // reading of AutoCAD's DXF.
        let compared = notDecoded(ours.skippedByLayer).filter {
            theirs.skippedByLayer[$0.key] != nil
        }
        for (type, layers) in compared {
            #expect(layers == theirs.skippedByLayer[type], "\(release) \(type)")
        }
        #expect(
            Set(compared.keys).isSuperset(of: ["MLINE", "MESH", "ACAD_TABLE", "3DSOLID", "IMAGE"]),
            "\(release) \(compared.keys.sorted())")
        // Not on layer 0: two MLINEs, a MESH and an ACAD_TABLE, which is the acceptance for the
        // layer: they are counted under their layer, not under 0.
        #expect(compared["MLINE"]?["Layer_true_color"] == 2, "\(release)")
        #expect(compared["MESH"]?["Layer_color_80"] == 1, "\(release)")
        #expect(compared["ACAD_TABLE"]?["Layer1"] == 1, "\(release)")

        // The same inside the blocks, by block name.
        for block in ours.blocks {
            guard let other = theirs.blocks.first(where: { $0.name == block.name }) else {
                continue
            }
            let inBlock = notDecoded(block.skippedByLayer).filter {
                other.skippedByLayer[$0.key] != nil
            }
            for (type, layers) in inBlock {
                #expect(
                    layers == other.skippedByLayer[type], "\(release) \(block.name) \(type)")
            }
        }
    }

    @Test(
        "the R14 drawing counts them on the layers the R2000 DXF of it has, in R14's upper case",
        .enabled(if: Fixtures.corpus != nil))
    func r14Layers() throws {
        let corpus = try #require(Fixtures.corpus)
        let ours = try DWG.read(
            data: try Data(contentsOf: corpus.appendingPathComponent("sample_AC1014.dwg")))
        let theirs = try DXF.read(
            contentsOf: corpus.appendingPathComponent("sample_AC1015_ascii.dxf"))
        func upperCased(_ layers: [String: Int]) -> [String: Int] {
            Dictionary(uniqueKeysWithValues: layers.map { ($0.key.uppercased(), $0.value) })
        }
        var compared = 0
        for (name, layers) in ours.skippedByLayer {
            guard case .notDecoded(let type)? = DWG.SkippedKind(typeName: name),
                let expected = theirs.skippedByLayer[type]
            else { continue }
            compared += 1
            #expect(layers == upperCased(expected), "\(type)")
        }
        #expect(compared >= 8)
        #expect(
            ours.skippedByLayer["NOT_DECODED_MLINE"]?["LAYER_TRUE_COLOR"] == 2,
            "\(ours.skippedByLayer["NOT_DECODED_MLINE"] ?? [:])")
    }

    @Test(
        "no record in the DXF text holds a handle and no more, but the markers and SEQEND",
        .enabled(if: Fixtures.corpus != nil), arguments: ["AC1014"] + DrawingOracleTests.releases)
    func noBareRecord(release: String) throws {
        let corpus = try #require(Fixtures.corpus)
        let data = try Data(contentsOf: corpus.appendingPathComponent("sample_\(release).dwg"))
        var bare: [String: Int] = [:]
        for record in DXFGroups.records(text: try DWG.dxfText(data: data)).values
        where record.groups.allSatisfy({ $0.code == 5 || $0.code == 67 }) {
            bare[record.type, default: 0] += 1
        }
        // A SEQEND closes the vertices or attributes before it and has nothing of its own.
        let others = bare.keys.filter { $0 != "SEQEND" && DWG.SkippedKind(typeName: $0) == nil }
        #expect(others.isEmpty, "\(release) \(bare)")
    }

    // MARK: The damaged file

    @Test(
        "an entity that is not decoded and whose object is damaged is counted as an object",
        .enabled(if: Fixtures.corpus != nil))
    func damagedUndecoded() throws {
        let corpus = try #require(Fixtures.corpus)
        let bytes = [UInt8](
            try Data(contentsOf: corpus.appendingPathComponent("sample_AC1032.dwg")))
        let whole = try ObjectStore(try Container(bytes))
        let document = try Document(store: whole)
        // The first MLINE of the drawing, which is on layer Layer_true_color.
        let mline = try #require(
            document.blocks.flatMap(\.entities).first {
                (try? whole.reader(for: $0))?.type == ObjectType.mline
            })

        var intact = DXFEmitter(document)
        let before = try #require(DXFGroups.records(text: intact.text())[mline])
        #expect(before.type == "NOT_DECODED_MLINE")
        #expect(before.first(8) != nil)

        for damaged in [
            DamagedFileTests.remove([mline], from: whole),
            try DamagedFileTests.overwrite([mline], in: whole),
        ] {
            var emitter = DXFEmitter(try Document(store: damaged))
            let after = try #require(DXFGroups.records(text: emitter.text())[mline])
            #expect(after.type == "UNREADABLE_OBJECT")
            #expect(after.first(8) == nil)
        }
    }
}
