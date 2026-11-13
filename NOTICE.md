# Notices and acknowledgements

SwiftDWG is MIT-licensed (see `LICENSE`). Its source follows other people's published work in the
ways listed here, and is checked against more. This file is where that is said in full.

## ACadSharp, MIT: the main source of the port

SwiftDWG is a Swift port of the DWG reader in [ACadSharp](https://github.com/DomCR/ACadSharp), a
C# library by Albert Domenech and its contributors, for the parts of it that SwiftDWG covers. A
source file that follows an ACadSharp file says so in its header, and names the ACadSharp file it
follows. The MIT licence below is ACadSharp's, reproduced as it requires, and it applies to the
parts of SwiftDWG that derive from it.

    MIT License

    Copyright (c) 2021 Albert Domenech

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

ACadSharp also publishes a `samples/` folder of DWG and DXF drawings in the same repository. It has
no licence file of its own and does not say who made each drawing, so this repository commits only
the few small ones its tests need, and says which in `Tests/SwiftDWGTests/Fixtures/README.md`. The
large ones are read from a local checkout of ACadSharp when `DWG_CORPUS` points at it, and are never
committed here.

## Open Design Specification for .dwg files

The format is implemented from the *Open Design Specification for .dwg files*, version 5.4.1,
copyright (c) 1998-2018 Open Design Alliance, Inc. The Open Design Alliance furnishes it for
informational use. This repository does not reproduce the document: its text, tables and figures
are not copied, and the descriptions in the source and in `docs/` are written afresh. What the
format fixes for interoperability, such as field order and constants, is of course in the code.

## Trademarks

DWG is the native file format of AutoCAD, and a trademark of Autodesk, Inc. AutoCAD is a trademark
of Autodesk, Inc. Teigha is a trademark of the Open Design Alliance. SwiftDWG is an independent
project. It is not affiliated with, endorsed by or sponsored by Autodesk or the Open Design
Alliance.

## Used only to check results, with no code taken

- [ezdxf](https://ezdxf.mozman.at/) (MIT): the reference reader that SwiftDXF, which SwiftDWG
  builds on, is validated against.
- [acadrust](https://github.com/hakanaktt/acadrust) (MPL-2.0): a Rust library that reads DWG. Its
  output on a drawing is compared with SwiftDWG's. None of its code is in this repository, so its
  licence does not reach it.
- AutoCAD's own DXF export of the same drawing, where one exists, is the reference that SwiftDWG's
  reading of a DWG is compared with.

## Deliberately not used

[LibreDWG](https://www.gnu.org/software/libredwg/) (GPL-3.0-or-later) is not used and its source
is not consulted, so that this package can stay MIT-licensed.
