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
