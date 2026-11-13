# CLAUDE.md

Guidance for Claude Code in this repository.

## Read first

- `okf/index.md`: the repo's OKF bundle (components, references, policies). Read the page the
  task needs, when it needs it.
- `NOTICE.md`: where the code comes from. It is a licence obligation, not decoration.

## Licence rules for the port (these are not optional)

- This package is MIT. It is a **port of ACadSharp (MIT)** plus the ODA specification, and the
  README says it is not clean-room.
- A source file that follows an ACadSharp file carries a header naming it (see any ported file),
  and `NOTICE.md` carries the ACadSharp licence text.
- **Never read or copy LibreDWG (GPL) source.** **Never copy acadrust (MPL-2.0) source.** Their
  *output* may be used to check results. Do not look at their code to work out how something is
  decoded.
- Do not reproduce text, tables or figures from the ODA specification. Write descriptions afresh.
- Test fixtures must have a licence that allows committing them. Say where each came from in
  `Tests/SwiftDWGTests/Fixtures/README.md`. Big third-party drawings stay out of the repository and
  are read from `DWG_CORPUS`.

## Build and test

```bash
swift build
swift test
swift-format lint --strict --recursive Sources Tests
swiftlint lint --strict
```

## Conventions

- Swift Testing (`@Suite` / `@Test` / `#expect`). Never `#expect(x != nil); #expect(x!.y)`: use
  `if let x { #expect(x.y) }`.
- swift-format `--strict`: a doc comment's summary line ends with a period and is followed by a
  blank `///` line.
- No em-dashes and no "honest" or "you're right" in prose (`okf/policies/writing-style.md`).
- Docs ship with the change (`okf/policies/docs-current.md`).
- Correctness is shown against AutoCAD's own DXF export of the drawing, not against SwiftDWG's
  output.
