# Font assets — D-039 "Editorial" (Route A)

**INTEGRATED 2026-10-31.** All files below are present in this
directory and declared in `pubspec.yaml`; the app now renders
the real faces (fallbacks in `lib/core/theme.dart` remain as
safety nets only). Provenance: official static instances
served by Google Fonts (Playfair Display 1.203, DM Sans
4.004, DM Mono 1.000), verified by name table + OS/2 weight
class + italic flag, none of them variable fonts. Licences:
the three `OFL-*.txt` files beside the fonts (SIL OFL 1.1).
Guarded by `test/font_assets_test.dart`, which loads the
FontManifest and the font bytes from the built bundle.

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
