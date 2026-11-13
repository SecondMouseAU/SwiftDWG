# Test fixtures

Only drawings with a licence that allows committing them are here. Larger ones are read from a
local checkout of ACadSharp's `samples/` folder when the environment variable `DWG_CORPUS` points
at it, and the tests that need them skip when it does not.

| File | Version | From | Licence |
|---|---|---|---|
| `empty.dwg` | AC1032 | ACadSharp `samples/sample_base/empty.dwg`, at commit `5b01af2`, unmodified | MIT (ACadSharp, see `NOTICE.md`) |

ACadSharp's `samples/sample_base/save_samples.lsp` is the AutoCAD script that saved the `sample_*`
drawings and their DXF exports from one drawing, so the DXF beside each is AutoCAD's own export of
the same drawing. That is what the larger corpus is compared with.
