# SwiftDWG

A native-Swift reader for **DWG**, AutoCAD's binary drawing format, that returns the same drawing
model as [SwiftDXF](https://github.com/SecondMouseAU/SwiftDXF): entities with layers, a stable
identity for each (its handle), blocks and tables. No binary, no subprocess, no C or Rust
dependency, so it builds wherever Swift does.

> **Status: working, not released.** `DWG.read` returns the drawing for R2000 to R2018 files and
> matches AutoCAD's own DXF export of the same drawings on the six releases that have a sample.
> There is no tagged release yet, and the [limits](#limits) below are real. Try it on your own
> files before relying on it.

## Why

Reading a DWG today means a converter program or a commercial SDK. When this package was started,
a search found no Swift package that reads DWG under a permissive licence. SwiftDXF and SwiftJWW
read their formats in plain Swift, and DWG is the format neither can reach. SwiftDWG closes that
gap, with the same shape: one import, one model.

## Use

```swift
import SwiftDWG
import SwiftDXF

let drawing = try DWG.read(contentsOf: url)      // a DXF.Drawing, the same model SwiftDXF gives
drawing.entities                                 // lines, arcs, circles, polylines, text, dimensions, ...
drawing.identities[0].handle                     // the entity's handle, as in the DXF
drawing.layers, drawing.lineTypes, drawing.blocks, drawing.dimensionStyles

// Block references and paper space are handled by SwiftDXF's options:
let flat = try DWG.read(contentsOf: url, options: .init(expandBlocks: true))

DWG.version(of: data)                            // .ac1032, the release it was saved as
let dxf = try DWG.dxfText(data: data)            // the DXF text the drawing is read from
```

A DWG is read into DXF text, which SwiftDXF then reads, so a drawing from a DWG goes through the
same code as one from a DXF: the same handling of extrusions, block references, paper space and
identities. `DWG.dxfText` shows that text, which is also a way to convert a DWG to a DXF.

## Status

| Release | Read | Checked against AutoCAD's DXF of the same drawing |
|---|---|---|
| R2018 `AC1032`, R2013 `AC1027`, R2010 `AC1024`, R2004 `AC1018` | yes | yes, whole drawing |
| R2007 `AC1021` | yes | yes, whole drawing |
| R2000 `AC1015` | yes | yes, whole drawing |
| R14 `AC1014` | yes | partly: no DXF of its own, compared with the R2000 one for the simple entities |
| R13 `AC1012` | written, never run | no sample file |
| R12 `AC1009` and older | no | not planned: neither the specification nor the code this is ported from covers them |

Of the 267 entities in each sample drawing, 262 are identical to what SwiftDXF reads from
AutoCAD's DXF, on every release from R2000 on. The layer, line type, dimension style, block, unit
and extents tables agree, with the exceptions in the next section.

## Limits

What is not the same as AutoCAD's DXF, each of which a test pins:

- **Splines kept as fit points only.** AutoCAD R2013 and later may store a spline as its fit
  points, where its DXF has computed control points and knots. SwiftDWG gives the fit points and
  no control points.
- **Leader hook lines.** The DWG holds no vertex for the hook line, and AutoCAD adds one when it
  writes DXF. SwiftDWG gives the vertices the DWG has.
- **True colours.** An entity's true colour comes with the palette index AutoCAD chose. A layer's
  does not, so its index is the nearest in RGB, which AutoCAD picks differently now and then.
- **Not decoded:** polyface and polygon meshes (skipped as `POLYFACE_MESH`, `POLYGON_MESH`), and
  the attributes of an insert. Other entities SwiftDXF does not model (images, solids, tables) are
  tallied in `skipped` by name, as for a DXF.
- **An entity that cannot be read** is left out, and counted in `skipped` as `UNREADABLE_<type>`.
  A layer, line type, text style, dimension style or block record that cannot be read is also left
  out, but nothing counts it: entities on a missing layer read as layer `0`.
- **Text in a code page SwiftDWG has no table for.** A file before R2007 names the code page of
  its single-byte text in its header. SwiftDWG decodes the ones in `Internal/CodePage.swift` and
  reads any other, such as the DOS and the double-byte Asian pages, as Windows-1252, so that text
  can come out wrong. R2007 and later files store text as UTF-16 and are not affected.
- **Anonymous block names** keep their DWG numbers; AutoCAD's DXF renumbers them.
- Performance has not been measured.

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
