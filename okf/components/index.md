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
  named section back together from its compressed pages (`Container.section(_:)`). R13 to R2000 and
  R2007 files are not read yet.
- **Errors** (`Errors.swift`): `DWG.Error` (`notADWG`, `unsupportedVersion`, `truncated`,
  `invalid`).
- **Classes and object map** (`Internal/Classes.swift`, `Internal/ObjectMap.swift`): the file's
  custom classes by number, and the offset of every object by handle. `ObjectStore` ties them to
  the objects section and decodes an object on request.
- **Object reader** (`Objects/ObjectReader.swift`, `Objects/EntityCommon.swift`): an object's three
  runs of bits (data, strings from R2007, handles), the data every object starts with, and the
  common part of every entity (layer, colour, line type, owner). `Objects/Geometry.swift` decodes
  `LINE`, `CIRCLE`, `ARC` and `POINT`.
- **Oracle tests** (`Tests/SwiftDWGTests/EntityOracleTests.swift`): decoded entities against the ones in
  AutoCAD's own DXF export, by handle.
- **Dimensions, leaders and hatches** (`Objects/Dimensions.swift`, `Objects/Leader.swift`,
  `Objects/Hatch.swift`, `Objects/DimensionsSupport.swift`): `DIMENSION` of all seven kinds
  (`DimensionData`: definition points, text, rotations, the measurement, the type code as DXF
  group 70 composes it, the style and anonymous block handles), `LEADER` and `HATCH` (boundary
  paths of polylines and of line, arc, ellipse and spline edges, pattern lines, seed points,
  gradient). Compared with AutoCAD's DXF on R2004 to R2018 in `DimensionsTests`, `LeaderTests` and
  `HatchTests`; `DimensionsSupportTests` builds objects no sample has. The R2000 and R2007 paths
  are ported but not checked against a file.
