# SwiftDWG

A native-Swift reader for **DWG**, AutoCAD's binary drawing format, that returns the same drawing
model as [SwiftDXF](https://github.com/SecondMouseAU/SwiftDXF): entities with layers, a stable
identity for each (its handle), blocks and tables. No binary, no subprocess, no C or Rust
dependency, so it builds wherever Swift does.

> **Status: 0.2.0.** `DWG.read` returns the drawing for R14 to R2018 files and matches AutoCAD's
> own DXF export of the same drawings on every release that has one to compare (R14 does not, see
> the [status](#status) table). The [limits](#limits) below are real. Try it on your own files before relying on it.

## Why

Reading a DWG today means a converter program or a commercial SDK. When this package was started,
a search found no Swift package that reads DWG under a permissive licence. SwiftDXF and SwiftJWW
read their formats in plain Swift, and DWG is the format neither can reach. SwiftDWG closes that
gap, with the same shape: one import, one model.

## Install

```swift
dependencies: [
    .package(url: "https://github.com/SecondMouseAU/SwiftDWG.git", from: "0.2.0")
],
targets: [
    .target(name: "YourTarget", dependencies: [.product(name: "SwiftDWG", package: "SwiftDWG")])
]
```

SwiftDWG depends on [SwiftDXF](https://github.com/SecondMouseAU/SwiftDXF) 0.4.0 or later, whose
drawing model it returns, and on nothing else.

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
DWG.readerVersion                                // "0.2.0", the release of SwiftDWG that read it
let dxf = try DWG.dxfText(data: data)            // the DXF text the drawing is read from

// What the reader left out is in drawing.skipped and drawing.skippedByLayer, under names that say
// why. DWG.SkippedKind tells them apart:
for type in drawing.skipped.keys {
    switch DWG.SkippedKind(typeName: type) {
    case .notDecoded(let type)?: print("\(type): the reader does not decode it yet")
    case .unreadable?, .unreadableObject?, .unreadableTableRecord?: print("\(type): damaged")
    case nil: print("\(type): SwiftDXF does not model it")
    }
}
```

`DWG.readerVersion` is this package's own release, equal to its git tag. Keep it beside a drawing
that was read, as a record of which release read it: two releases can read the same file
differently, and a changed result can be traced to a changed reader only with it. The release
process checks that it equals the tag.

A DWG is read into DXF text, which SwiftDXF then reads, so a drawing from a DWG goes through the
same code as one from a DXF: the same handling of extrusions, block references, paper space and
identities. `DWG.dxfText` shows that text, which is also a way to convert a DWG to a DXF.

## Status

| Release | Read | Checked against AutoCAD's DXF of the same drawing |
|---|---|---|
| R2018 `AC1032`, R2013 `AC1027`, R2010 `AC1024`, R2004 `AC1018` | yes | yes, whole drawing |
| R2007 `AC1021` | yes | yes, whole drawing |
| R2000 `AC1015` | yes | yes, whole drawing |
| R14 `AC1014` | yes | partly: no DXF of its own, compared with the R2000 one for the simple entities, and by handle for the lightweight polylines and hatches |
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
- **Attributes** (`ATTRIB`, `ATTDEF`) are decoded for R14 to R2018 and written to the DXF text as
  AutoCAD writes them: an `INSERT` with group 66 set, its `ATTRIB` records, then its `SEQEND`; the
  `ATTDEF` records in their block. Every record equals AutoCAD's DXF group for group on the six
  releases with a sample (R14 is compared with the R2000 export, field by field). A multi-line
  attribute (R2018) is written with its embedded text after group 101, as AutoCAD does. What of
  that SwiftDXF models is up to its version: 0.6.0 models attributes, 0.4.0 tallies them in
  `skipped`. Extended data is written as for any entity; the owner (group 330), the subclass
  markers (group 100) and the extension dictionary (group 102) are not written, as for the other
  entities.
- **Not decoded:** polyface and polygon meshes, as well as every
  other entity of a type the reader does not decode, such as a `VIEWPORT`, an `IMAGE`, a `3DSOLID`,
  an `MLINE`, a `MESH`, a `MULTILEADER` or a proxy entity (`ACAD_PROXY_ENTITY`). Each is counted, and none is written as a record of its
  own type, which SwiftDXF would read as an entity with nothing in it where it models the type.
  It is written as a marker named `NOT_DECODED_<type>` (`DWG.notDecodedPrefix`), so `skipped` has
  `NOT_DECODED_VIEWPORT` where a DXF read has `VIEWPORT`. That keeps three things apart: a type the
  DWG reader does not decode (`NOT_DECODED_`), a type the drawing model does not model (the plain
  name, as for a DXF, for what the reader writes as itself), and a damaged file (`UNREADABLE_`).
  The marker carries the entity's layer, so `skippedByLayer` counts it under the layer it is on, as
  AutoCAD's DXF of the drawing does for the same entity. It has none, and is counted on layer `0`,
  when the file's layer handle for it cannot be read, or the layer is lost.
- **TOLERANCE and WIPEOUT** are decoded, from R14 to R2018, and written to the DXF text with the
  groups AutoCAD's DXF has for them. SwiftDXF models them from 0.6.0; an earlier SwiftDXF tallies
  them in `skipped`, as for any entity it does not model. The text of a tolerance is the frame as
  AutoCAD writes it (`{\Fgdt;i}%%v0.012%%v%%vB`). The masked area of a wipeout is its clip boundary,
  in pixels of the image rectangle the file keeps it in.
- **An entity that cannot be read** is left out, and counted among the skipped types as
  `UNREADABLE_<type>` (`DWG.unreadablePrefix`): in `skipped`, or in the block's `skippedByLayer` for
  an entity in a block, on its layer when that was read before the entity failed. One whose object
  cannot be opened, or that the file does not hold, has no type to name and is counted as
  `UNREADABLE_OBJECT`, with no layer. A 2D or 3D polyline with a vertex that cannot be read is
  counted whole as `UNREADABLE_POLYLINE`, since one a point short is a different shape. So is a
  layer, line type, text style, dimension style or block record, as `UNREADABLE_LAYER`,
  `UNREADABLE_LTYPE`, `UNREADABLE_STYLE`, `UNREADABLE_DIMSTYLE` or `UNREADABLE_BLOCK_RECORD`
  (`DWG.unreadableTableTypes`); entities on a lost layer read as layer `0`. A control object of one
  of those tables that cannot be read stops the read with a `DWG.Error`, as every record of its
  table is reached through it.
- **Naming what was left out.** The two prefixes, the table names and the names built from them are
  exported as `DWG.SkippedKind`: `DWG.SkippedKind(typeName:)` classifies a key of `skipped` as
  `.notDecoded`, `.unreadable`, `.unreadableObject` or `.unreadableTableRecord`, or `nil` for any
  other. The reader writes its markers through the same type, so the two cannot differ.
- **A corrupt file** ends in a `DWG.Error`, or in a drawing that counts what it lost; it is not
  meant to stop the process with a trap or to never return, and memory is bounded by the sizes the
  file declares. That is checked by inverting single bytes: in the committed drawings, every byte
  of the file header and one in 1,009 of the rest, and on a developer machine in the AutoCAD
  samples, the first 1,280 bytes and some 250 more of each. It is not proved for every byte of
  every file, so a file found to trap or hang is a bug to report.
- **Three or more unreadable entities in one block, before R2004.** In those files each entity
  names the one before it and the one after it. An entity that cannot be read is counted and the
  others are kept: the links are followed from both ends of the block, and what lies between two
  unreadable entities is found by its owner, in handle order, so a block's drawing order can be
  lost there. An entity whose own header cannot be read, and that lies between two other
  unreadable ones, names no owner that can be read, so it is neither kept nor counted.
- **Text in a code page SwiftDWG has no table for.** A file before R2007 names the code page of
  its single-byte text in its header. SwiftDWG decodes the ones in `Internal/CodePage.swift` and
  reads any other, such as the DOS and the double-byte Asian pages, as Windows-1252, so that text
  can come out wrong. R2007 and later files store text as UTF-16 and are not affected.
- **Anonymous block names** keep their DWG numbers; AutoCAD's DXF renumbers them.
- Performance has not been measured.

## The header in `dxfText`

The HEADER section of `DWG.dxfText` has the system variables a DWG stores, with the group codes
and in the order of AutoCAD's own DXF: 196 variables for an R2000 drawing and 248 for an R2018 one.
A variable that only some releases store is written for those releases only. A variable DXF writes
as the name of an object (`$CLAYER`, `$TEXTSTYLE`, `$CELTYPE`, `$DIMSTYLE`, `$CMLSTYLE`,
`$DIMTXSTY`, `$DIMBLK` and the others of the dimension style, the user coordinate systems) is
written with the name of the object the file's handle points at. `DWG.read` therefore gives
SwiftDXF the drawing's current dimension style and text style, `$DIMSCALE`, `$LUNITS`, `$LUPREC`
and the rest.

`$DWGCODEPAGE` comes from the file header, and is named for the Windows pages 1250 to 1254 only
(`ANSI_1252` in every sample).

`$MEASUREMENT` (0 English, 1 metric) is not in the header section of a DWG. The file keeps it in
its `AcDb:Template` section, and SwiftDWG reads it from there, for every release. It is 0 in
every drawing that has an AutoCAD DXF, so those do not show that a metric drawing reads as 1.
`aec_objects/AecObjects.dwg` has no DXF, and reads as 1 with `$INSUNITS` 4 (millimetres), where
`svg/export_sample.dwg`, also in millimetres, reads as 0: the value is read, and is a setting of
its own, but it is not checked against AutoCAD for a metric drawing.

Compared with AutoCAD's own DXF of 17 drawings (the six releases R2000 to R2018 of one drawing, ten
dynamic block drawings, and a georeferenced drawing from another machine), every variable written
is in AutoCAD's DXF, in the same order, with the same group codes, and the same value, with these
exceptions, which a test (`HeaderTextTests`) pins:

- **Drawings exported from another save.** The six releases of the sample drawing are AutoCAD's
  export of the same save as each DWG, and are compared strictly. The ten dynamic block drawings
  and the georeferenced one have a DXF from a copy that was edited or saved again, so for them the
  variables an edit changes may differ: the extents, the times, the next handle and the drawing's
  GUID. Every other variable is compared as for the rest.
- **Reals.** AutoCAD prints a real with 16 significant digits, SwiftDWG with as many as the
  double needs, so a few differ in the last digit of the text. They are compared as numbers with a
  relative tolerance of 1e-15, which is the most that printing 16 digits can change. Times are
  printed to 9 or 10 decimals of a day, and are compared to 1e-9 of a day.
- **`$HANDSEED`, `$VERSIONGUID`, `$TDUUPDATE`, `$TDINDWG`, `$TDUSRTIMER`.** AutoCAD exported the
  DXF after the DWG, so the next handle is higher, the last save and the two times it moves on are
  about a second later, and the version GUID is a new one. SwiftDWG writes what the DWG holds.
- **`$CECOLOR` of a true colour.** DXF has no place for the colour and writes the palette index
  AutoCAD picked for it, 193 where the nearest in RGB is 181. SwiftDWG writes the nearest, as it
  does for a layer. Dimension colours are indexes in the file and are exact.
- **`$XCLIPFRAME` before R2010.** The R2004 and R2007 DWGs hold 2, a value the format only gave
  meaning to in R2010, and AutoCAD's DXF of them has 0. SwiftDWG writes 0 for a value above 1 in
  those releases. Only two drawings show this.
- **`$CMLSTYLE`** is the name the style has in the multiline style dictionary (`Standard`), which
  is what DXF writes, and not the name stored in the style (`STANDARD`).
- **`$DIMBLK`, `$DIMBLK1`, `$DIMBLK2`, `$DIMLDRBLK`** name one of AutoCAD's own arrowheads
  without the underscore of its block (`BoxBlank` for `_BoxBlank`), as DXF does.

Decoded and not written, because AutoCAD's DXF does not write them (they live in the registry, or
in the dimension style table) or because there is nothing to check them against:

| Variables | Why |
|---|---|
| `$FACETRES`, `$ISOLINES`, `$PELLIPSE`, `$TEXTQLTY`, `$TSTACKALIGN`, `$TSTACKSIZE` | AutoCAD's DXF of every sample omits them |
| `$DIMALTMZF`, `$DIMALTMZS`, `$DIMMZF`, `$DIMMZS` (R2010 and later) | dimension style variables, which DXF has in the DIMSTYLE table only |
| `$DRAGVS` | null in every sample, where AutoCAD's DXF omits it; no sample has it set |
| `$DIMFIT`, `$DIMUNIT`, `$DIMSAV`, `$DELOBJ`, `$PICKSTYLE` (R14) | there is no AutoCAD DXF of an R14 drawing to show they are written |

In AutoCAD's DXF and not in the DWG's header section, so not written:

| Variables | Why |
|---|---|
| `$ACADMAINTVER` | the file header's byte equals it in 4 of the 6 samples and not in R2000 and R2018, so it is not derived |
| `$LASTSAVEDBY` | kept in the summary information section, which is not read |
| `$TDCREATE`, `$TDUPDATE` (R2000 and later) | the DWG keeps the universal times (`$TDUCREATE`, `$TDUUPDATE`, written); DXF's local times add the exporting machine's offset |
| `$REALWORLDSCALE` | the DWG has an unexplained bit where it sits, 1 in every sample, so the bit cannot be told from a constant |

AutoCAD's DXF names its default visual styles in `$INTERFEREOBJVS` and `$INTERFEREVPVS` where a
DWG's header has null handles (the georeferenced drawing). SwiftDWG writes the variable only when
the handle is set. The handles that are not variables (the table control objects, the dictionaries
and the built-in line types) belong to the TABLES and OBJECTS sections and are not in the header.

What is not checked: a user coordinate system that is named (no sample has one, so `$UCSNAME` and
the like are empty in every comparison), a drawing whose `$CEPSNTYPE` is 3 (its `$CPSNID` is not
written), and R14, which has no AutoCAD DXF. The R14 header is checked for its order and its names
against the R2000 and R12 DXF of the corpus, and the six variables R14 keeps and R2000 moved to the
registry (`$DRAGMODE`, `$OSMODE`, `$BLIPMODE`, `$COORDS`, `$ATTDIA`, `$ATTREQ`) are placed where
AutoCAD's R12 DXF has them.

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
