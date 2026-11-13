---
type: repo
title: SwiftDWG
resource: https://github.com/SecondMouseAU/SwiftDWG
tags: [dwg, autocad, 2d, import, drawing, swift]
description: Native-Swift reader for DWG (AutoCAD's binary drawing format) into the SwiftDXF drawing model.
timestamp: 2026-11-13
---

# SwiftDWG

A **native-Swift reader for DWG**, AutoCAD's binary format, returning the `DXF.Drawing` model of
SwiftDXF so a drawing is read the same way whatever its format. Pure Swift, no binary. A port of
the DWG reader in ACadSharp (MIT) and the Open Design Alliance's specification, MIT-licensed, and
not clean-room: see `NOTICE.md`.

## Role in the ecosystem

- **Cluster:** kernel
- **Depends on:** SwiftDXF (the drawing model)
- **Feeds products:** DWG import for the OCCTSwift CAD I/O stack. OCCTSwiftIO's `DWGLoader` runs
  an external converter today, and is meant to move to this package (OCCTSwiftIO#58).

## Components

See [`components/`](components/index.md) for the public surface.

## References

See [`references/`](references/index.md) for the format, the code this is ported from, and what it
is checked against.

## Policies

- [Query `context` first for OCCT / OCCTSwift docs](policies/context-first.md)
- [Documentation updates are mandatory](policies/docs-current.md)
- [No em-dashes, banned words in prose](policies/writing-style.md)
- [Search before building](policies/search-before-building.md)
- [Code structure](policies/code-structure.md)
- [Issue labels and project-board tracking](policies/issue-tracking.md)
- [Code style](policies/code-style.md)
