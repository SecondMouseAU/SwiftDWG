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
- **DXF writer** (`Internal/DXFWriter.swift`): writes group codes and values as ASCII DXF. A drawing
  read from a DWG is handed to SwiftDXF as DXF text, so that it goes through the same code as one
  that came from a DXF (extrusions, block references, paper space, identities).
