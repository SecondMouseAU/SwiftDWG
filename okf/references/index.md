---
type: reference
title: References index
resource: https://github.com/SecondMouseAU/SwiftDWG
tags: [index]
description: The format, the code SwiftDWG is ported from, and what it is checked against.
timestamp: 2026-11-13
---

# References

- **Open Design Specification for .dwg files**, version 5.4.1 (Open Design Alliance): the format.
  Informational use only; its text is not reproduced here. A copy is in the ACadSharp repository
  under `reference/`.
- **ACadSharp** (MIT), <https://github.com/DomCR/ACadSharp>: the C# reader this is ported from.
  Per-file credit is in each ported file's header and in `NOTICE.md`.
- **SwiftDXF** (MIT), <https://github.com/SecondMouseAU/SwiftDXF>: the drawing model SwiftDWG
  produces, and the reader for AutoCAD's own DXF exports that results are compared with.
- **ezdxf** (MIT), <https://ezdxf.mozman.at/>: the reference DXF reader SwiftDXF is validated
  against.
- **acadrust** (MPL-2.0), <https://github.com/hakanaktt/acadrust>: an independent DWG reader whose
  output is compared with SwiftDWG's. No code is taken from it.
- **LibreDWG** (GPL): not used and not consulted, so this package stays MIT.
