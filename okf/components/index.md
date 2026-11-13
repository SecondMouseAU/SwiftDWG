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
