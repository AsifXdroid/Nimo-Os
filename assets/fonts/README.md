# Font assets — D-039 "Editorial" (Route A, owner-supplied)

The Editorial type system (Playfair Display / DM Sans / DM Mono,
all SIL Open Font License 1.1) is wired in `lib/core/theme.dart`
by family name WITH platform fallbacks, so the app builds and
runs correctly before these binaries land. **Do not add the
pubspec `fonts:` block until every file below is present** —
referencing a missing asset breaks the build.

## Files to place in THIS directory (exact names)

| File | Family | Weight / style |
|---|---|---|
| `PlayfairDisplay-Medium.ttf` | Playfair Display | 500 |
| `PlayfairDisplay-SemiBold.ttf` | Playfair Display | 600 |
| `PlayfairDisplay-MediumItalic.ttf` | Playfair Display | 500 italic |
| `DMSans-Regular.ttf` | DM Sans | 400 |
| `DMSans-Medium.ttf` | DM Sans | 500 |
| `DMSans-Bold.ttf` | DM Sans | 700 |
| `DMMono-Regular.ttf` | DM Mono | 400 |
| `DMMono-Medium.ttf` | DM Mono | 500 |

## Licence files to place alongside (OFL requirement)

- `OFL-PlayfairDisplay.txt`
- `OFL-DMSans.txt`
- `OFL-DMMono.txt`

(each family's `OFL.txt` from its Google Fonts / GitHub source,
renamed as above so all three can live in one directory).

## Notes

- DM Sans 600 is intentionally not bundled: the owner's Route A
  set is 400/500/700. Semibold (w600) requests in the type roles
  resolve to the 700 face by font matching.
- Source of truth for downloads: fonts.google.com (each family's
  "Download family" zip contains the static .ttf files + OFL.txt).
- Once the files are in the repo, the pubspec wiring is a small
  text-only follow-up commit (families `Playfair Display`,
  `DM Sans`, `DM Mono` pointing at the assets above) — after
  that, CI builds ship the real faces and the fallbacks stop
  being exercised.
