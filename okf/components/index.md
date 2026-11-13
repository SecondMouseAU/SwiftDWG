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
