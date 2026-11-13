# SwiftDWG

A native-Swift reader for **DWG**, AutoCAD's binary drawing format, that returns the same drawing
model as [SwiftDXF](https://github.com/SecondMouseAU/SwiftDXF): entities with layers, a stable
identity for each (its handle), blocks and tables. No binary, no subprocess, no C or Rust
dependency, so it builds wherever Swift does.

> **Status: early.** The package is being built in the open. What works today is listed under
> [Status](#status); the rest is the plan. Do not rely on it for real files yet.

## Why

Reading a DWG today means a converter program or a commercial SDK. When this package was started,
a search found no Swift package that reads DWG under a permissive licence. SwiftDXF and SwiftJWW
read their formats in plain Swift, and DWG is the format neither can reach. SwiftDWG closes that
gap, with the same shape: one import, one model.

## Use

```swift
import SwiftDWG

let data = try Data(contentsOf: url)
DWG.looksLikeDWG(data)      // true for a DWG
DWG.version(of: data)       // .ac1032, the format release it was saved as
```

Reading the drawing itself, `DWG.read(contentsOf:)` returning a `DXF.Drawing`, is the goal and is
not there yet.

## Status

| Piece | State |
|---|---|
| Version detection (`AC1006` to `AC1032`) | done |
| Bit-coded values (`BS`, `BL`, `BD`, `DD`, handles, text) | done |
| File header, section map, decompression (R2004 and later: `AC1018`, `AC1024`, `AC1027`, `AC1032`) | done, checked on an `AC1032` file |
| Classes, object map, the object stream and the data every entity starts with | done, checked on `AC1018`, `AC1024`, `AC1027`, `AC1032` |
| Header variables (R2004 and later), equal to AutoCAD's DXF export of the same drawings | done: see below |
| Entities: `LINE`, `CIRCLE`, `ARC`, `POINT` | done, equal to AutoCAD's DXF on four releases |
| Other entities and the tables, into `DXF.Drawing` | planned |
| R13 to R2000 files (`AC1012`, `AC1014`, `AC1015`): container, classes, object map, base entities | done, checked on `AC1014` and `AC1015` |
| R2007 (`AC1021`): container with its own compression, classes, object map, base entities | done, checked on `AC1021` |
| R12 and older (`AC1009` and before) | not planned: neither the specification nor the code this is ported from covers them |

## How it is checked

Every drawing that is read is compared with AutoCAD's own DXF export of the same drawing, read by
SwiftDXF: same entities, same coordinates, same handles. Where no export exists the result is
compared with the output of an independent reader. The expected values come from those, not from
SwiftDWG's own output.

## Provenance and licence

MIT. SwiftDWG is a Swift port of the DWG reader in [ACadSharp](https://github.com/DomCR/ACadSharp)
(MIT), together with the Open Design Alliance's published specification for the format. It is **not**
a clean-room implementation, and says so. See [`NOTICE.md`](NOTICE.md) for the full
acknowledgements, the ACadSharp licence text, and what was deliberately not used (LibreDWG, which
is GPL).

DWG is a trademark of Autodesk, Inc. This project is independent of Autodesk and of the Open Design
Alliance.
