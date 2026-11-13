---
type: component
title: Components index
resource: https://github.com/SecondMouseAU/SwiftDWG
tags: [index]
description: Public modules and API surfaces exposed by SwiftDWG.
timestamp: 2026-11-13
---

# Components

- **`SwiftDWG`** (library): `DWG.version(of:)` and `DWG.looksLikeDWG(_:)` tell a DWG, and the
  release it was saved as (`DWG.Version`, `AC1006` to `AC1032`), from its first bytes
  (`Version.swift`). Reading the drawing into a `DXF.Drawing` is planned; see the README status
  table.
- **Bit reader** (`Internal/BitReader.swift`): the bit-coded values a DWG is made of, at any bit
  position (`BB`, `BS`, `BL`, `BLL`, `BD`, `DD`, `MC`, `MS`, handles, text), with a version-aware
  extrusion, thickness and text. Every read that runs past the end throws, never traps.
- **Container** (`Internal/Container.swift`, `Internal/LZ77.swift`): the outer structure of an
  R2004 or later file. It decrypts the header, reads the page map and the section map, and puts a
  named section back together from its compressed pages (`Container.section(_:)`). R13 to R2000 files (`AC1012` to
  `AC1015`) have no pages: the header lists where each section is, and the objects are addressed by
  position in the whole file. R2007 files (`AC1021`) use a different
  page layout: Reed-Solomon interleaving and their own LZ77 (`Internal/LZ77AC21.swift`).
- **Header variables** (`Internal/HeaderReader.swift`, `HeaderReader+Dimensions.swift`,
  `HeaderVariables.swift`, `CodePage.swift`): reads the `AcDb:Header` section into a
  `HeaderVariables`, with the system variables under the names DXF gives them (`$INSUNITS`,
  `$EXTMIN`, `$DIMSCALE`) and the handles of the table control objects, the dictionaries and the
  current styles under ACadSharp's names (`BLOCK_CONTROL_OBJECT`, `CLAYER`, ...). From R2007 the
  text and the handles are read from their own streams. What is checked, and against what:
  - `AC1015`, `AC1018`, `AC1021`, `AC1024`, `AC1027`, `AC1032` against AutoCAD's own DXF export of
    the same drawing: every variable both have is equal, except the few the two saves cannot agree
    on (the next handle and the times a save moves on, a GUID that is new at each save, and true
    colours, which DXF writes as the nearest palette index).
  - `AC1014` has no DXF export, so it is compared with the `AC1015` one: the drawing's own state is
    equal, and the differences (a viewport count, a block name's case, the times) are named in
    the tests. It keeps the local creation and save times, `$TDCREATE` and `$TDUPDATE`, where R2000
    and later keep universal time.
  - For every release the handles the header names are looked up in the file's own object stream and
    must be objects of the right kind, which is the only check of R14's and R2000's two viewport
    entity header handles, as DXF does not write them.
  - R13 (`AC1012`) shares the R14 code and has no sample file, so it has never run.
- **Errors** (`Errors.swift`): `DWG.Error` (`notADWG`, `unsupportedVersion`, `truncated`,
  `invalid`).
- **Classes and object map** (`Internal/Classes.swift`, `Internal/ObjectMap.swift`): the file's
  custom classes by number, and the offset of every object by handle. `ObjectStore` ties them to
  the objects section and decodes an object on request.
- **Object reader** (`Objects/ObjectReader.swift`, `Objects/EntityCommon.swift`): an object's three
  runs of bits (data, strings from R2007, handles), the data every object starts with, and the
  common part of every entity (layer, colour, line type, owner). `Objects/Geometry.swift` decodes
  `LINE`, `CIRCLE`, `ARC` and `POINT`.
- **TEXT, MTEXT, INSERT, MINSERT** (`Objects/Text.swift`, `Objects/Insert.swift`,
  `Objects/TextSupport.swift`): `TextData`, `MTextData` and `InsertData` in the file's own terms
  (radians, OCS, handles for the text style, block record, attributes and SEQEND). ATTRIB and
  ATTDEF are not decoded; the insert keeps the handles assembly needs. `TextSupport.swift` holds
  the CMC colour read and the count check. Checked against AutoCAD's DXF in `TextTests.swift` and
  `InsertTests.swift`, and with constructed objects (`TextSupportTests.swift`) for the R13 to R2000
  and R2007 layouts the container cannot read yet.
- **Curves, polylines and surfaces** (`Objects/Curves.swift`, `Objects/Polylines.swift`,
  `Objects/Surfaces.swift`, `Objects/CurvesSupport.swift`): `ELLIPSE`, `SPLINE`, `LWPOLYLINE`, 2D
  and 3D `POLYLINE` with their `VERTEX` and `SEQEND`, `SOLID`, `TRACE` and `3DFACE`, in the file's
  own terms. A polyline carries the handles of its vertices and its `SEQEND`, for assembly. Compared
  with AutoCAD's DXF in `CurvesTests`, `PolylinesTests` and `SurfacesTests`; polyface and mesh
  polylines are not decoded yet.
- **Oracle tests** (`Tests/SwiftDWGTests/EntityOracleTests.swift`): decoded entities against the ones in
  AutoCAD's own DXF export, by handle.
- **DXF writer** (`Internal/DXFWriter.swift`): writes group codes and values as ASCII DXF. A drawing
  read from a DWG is handed to SwiftDXF as DXF text, so that it goes through the same code as one
  that came from a DXF (extrusions, block references, paper space, identities).
- **Dimensions, leaders and hatches** (`Objects/Dimensions.swift`, `Objects/Leader.swift`,
  `Objects/Hatch.swift`, `Objects/DimensionsSupport.swift`): `DIMENSION` of all seven kinds
  (`DimensionData`: definition points, text, rotations, the measurement, the type code as DXF
  group 70 composes it, the style and anonymous block handles), `LEADER` and `HATCH` (boundary
  paths of polylines and of line, arc, ellipse and spline edges, pattern lines, seed points,
  gradient). Compared with AutoCAD's DXF on R2004 to R2018 in `DimensionsTests`, `LeaderTests` and
  `HatchTests`; `DimensionsSupportTests` builds objects no sample has. The R2000 and R2007 paths
  are ported but not checked against a file.
- **Table records** (`Objects/TableRecords.swift`, `Objects/Tables*.swift`): the symbol tables and
  what hangs off them, read by `ObjectStore.tableRecord(_:)`: the control object of each table (its
  entry handles), block records, layers, line types, text styles, dimension styles (every variable
  the file stores), application names, dictionaries, layouts with their plot settings, and the
  `BLOCK` and `ENDBLK` entities. Handles stay numbers; naming them is left to the code that builds
  the drawing. `Tables*.swift` also holds the colour reader that table entries use.
- **Oracle tests** (`Tests/SwiftDWGTests/EntityOracleTests.swift`): decoded entities against the ones in
  AutoCAD's own DXF export, by handle.
- **Table oracle tests** (`Tests/SwiftDWGTests/TableOracleTests.swift`): the same comparison for
  the table records, by handle, field by field. Objects that only one of the two files of a sample
  has are counted, and the entries among them are paired by name.
- **Assembly** (`Assembly/Document.swift`, `DXFEmitter.swift`, `DXFEmitter+Entities.swift`,
  `Read.swift`): `DWG.read(contentsOf:)` loads the header, the tables and the blocks into a
  `Document`, resolves every handle to the name a DXF uses, writes the DXF text with AutoCAD's own
  group codes, and hands it to SwiftDXF. `DWG.dxfText(data:)` returns that text. The comparison with
  AutoCAD's DXF is in `Tests/SwiftDWGTests/DrawingOracleTests.swift`.
- **Colour and extended data** (`Internal/ColorIndex.swift`, `Internal/ExtendedData.swift`): the
  AutoCAD palette, used for the nearest index of a layer's true colour, and the decoder for the
  extended data an entity carries, which holds a dimension's style overrides.
