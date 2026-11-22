# Test fixtures

Only drawings with a licence that allows committing them are here. Larger ones are read from a
local checkout of ACadSharp's `samples/` folder when the environment variable `DWG_CORPUS` points
at it, and the tests that need them skip when it does not.

| File | Version | From | Licence |
|---|---|---|---|
| `empty.dwg` | AC1032 | ACadSharp `samples/sample_base/empty.dwg`, at commit `5b01af2`, unmodified | MIT (ACadSharp, see `NOTICE.md`) |
| `BLOCKPOINTPARAMETER.dwg` and `.dxf` | AC1032 | ACadSharp `samples/dynamic-blocks/`, same commit, unmodified | MIT (ACadSharp, see `NOTICE.md`) |

ACadSharp's `samples/sample_base/save_samples.lsp` is the AutoCAD script that saved the `sample_*`
drawings and their DXF exports from one drawing, so the DXF beside each is AutoCAD's own export of
the same drawing. That is what the larger corpus is compared with.

`BLOCKPOINTPARAMETER.dxf` is AutoCAD's own export of the drawing, which `EntityOracleTests` compares the
decoded entities with (by handle, coordinates exactly). The four larger `sample_AC10xx.dwg` files and
their `_ascii.dxf` exports, from the same folder, get the same comparison when `DWG_CORPUS` points at
`samples/`: 154 entities each, with no difference.

`ClassEntityTests` also reads one drawing that is not in ACadSharp's samples, when a copy of it is
in the `DWG_CORPUS` folder: `FD-0123_ﾀ550形550-551.dwg`, an R14 railway vehicle drawing from the
maintainer's own collection. It is third-party and is not committed. It has no DXF export, so its
lightweight polylines and hatches are compared with what acadrust 0.6.8 reads from it.

`AttributeTests` compares the ATTRIB and ATTDEF records, and the SEQEND of each INSERT, of the same
files with the same DXF exports group for group, and the R14 sample with the R2000 export by handle.
Every sample holds four attributes on two inserts and five definitions in two blocks, and R2018 a
multi-line attribute and definition. No committed drawing has an attribute, so those tests need
`DWG_CORPUS`.

`TableOracleTests` compares the table records, control objects, dictionaries and layouts of the same
files with the same DXF exports, by handle. AutoCAD creates some objects when it saves (round-trip
dictionaries and the like) and numbers them differently in the DWG and the DXF, so a few objects
exist under a handle in only one of the two files. The test pins how many, and pairs the table
entries among them by name.

`ToleranceTests` and `WipeoutTests` compare the TOLERANCE and WIPEOUT records of `DWG.dxfText` with
the same DXF exports, group by group: the three tolerances and the one wipeout of each of the six
`sample_AC10xx.dwg` files from R2000 to R2018, and, for the R14 file, the ones in the R2000 DXF.
The committed fixtures hold neither type.
