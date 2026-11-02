# Known Limitations, Blockers & Unverified Assumptions

## Blockers in the build environment
- **No Xcode was installed** on the build machine (only Command Line Tools for Swift 6.0.3). As a
  result:
  - The iOS app target has **not been compiled for iOS** or run on a simulator.
  - All app sources *were* type-checked against the macOS 14 SDK, including all SwiftUI views,
    with strict concurrency on.
  - The 115 unit tests ran on macOS through `scripts/test-cli.sh`.
  - Code inside `#if os(iOS)` has **not** been compiled:
    - ImageCaptureCore authorization;
    - navigation-bar modifiers;
    - `EditButton`.
- The UI tests (`FilmLabUITests`) are written but **have not run**.
- The CLT install has a stale duplicate `usr/include/swift/module.modulemap` that breaks every
  `import Foundation` ("redefinition of module 'SwiftBridging'"). The scripts mask it with a
  `-vfsoverlay` and do not modify system files. Xcode is unaffected.

## Hardware (nothing verified)
- No iPhone or X‑T30 III was available. **Every camera capability is NV/3P.** See `research.md`
  and the `ptp-validation.md` checks P1–P7.
- Apple doesn't state that iPhone + ImageCaptureCore can see a USB‑C PTP camera. Fuji Recipe
  Studio's iOS beta suggests it can; that is not verified by us.
- The order of the pass-through buffers on iOS is assumed from Apple's macOS-era sample. A
  fallback detects swapped order.
- **Render with Camera is disabled** on real hardware. The reported RAW-conversion sequence
  conflicts between sources and is not shown to leave C1–C7 unchanged. Demo mode exercises the
  UI with clearly labelled simulated output.
- **Slot writes over USB are off by default.** They sit behind an experimental toggle with a typed
  confirmation and a permanent warning banner.
- Several facts are disputed or unknown:
  - whether DR AUTO and D RANGE PRIORITY are stored in presets;
  - whether the slot name is written first or last;
  - the meaning of 0xD18E, 0xD18F, 0xD1A3, 0xD1A4 and 0xD1A5.

  FilmLab never writes the disputed codes.
- The slot-name limit (25 chars, limited ASCII) comes from community notes; the manual is silent.
- **Other camera bodies (see `docs/cameras.md`).**
  - Profiles for the 16 non-reference bodies are **community-reported (3P)**:
    - film simulations;
    - missing features (e.g. no CLASSIC Neg. on the X‑T3/X‑T30);
    - whole-step Highlight/Shadow on early X‑Trans IV.
  - They were not checked against each owner's manual. Firmware updates (e.g. REALA ACE on the X‑T5/X‑H2/X‑S20) can change them.
  - Enum values (white balance modes, DR, grain options) are assumed to match the X‑T30 III's on every body.
  - Smooth Skin Effect isn't modelled as a recipe setting on any body.
- **USB slot access is X‑T30 III only.**
  - Other recognised bodies connect as *profile only*: FilmLab neither reads nor writes their slots.
  - Reason: selecting a slot is itself a PTP property write, and the property map is unreported on those bodies.
- FS1–FS3 (FS RECIPE) are not readable or writable by FilmLab.

## Preview fidelity
- Looks are **FilmLab's own approximations**, not Fujifilm's processing, and are uncalibrated.
- **Highlight/Shadow** are approximated in a global LUT. The camera's actual tone response is
  unknown.
- **DR settings** are approximated as highlight protection. The real camera DR modes change
  exposure and ISO, which a JPEG preview can't reproduce.
- **White balance** on JPEG/HEIF assumes a ~5500 K source. AUTO, CUSTOM and AMBIENCE leave the
  photo's white balance unchanged.
- **Grain, clarity, sharpness and NR** are size-relative approximations, so a phone preview won't
  match pixel-level camera output.
- **RAF decoding** depends on Apple's `CIRAWFilter`. Compressed RAF support is unverified. That
  decode is Apple's rendering, which is why it is labelled "Original (Apple RAW decode)", never
  "As Shot".
- **Histogram** is computed from the displayed preview pixels, sampled to 256 px.
- **Golden-image fixtures** are regression values for FilmLab's own engine; they are not ground
  truth.

## Product scope not implemented yet
- Recipe import from a URL. Images, text and FilmLab JSON are supported; there is no web
  scraping, by design.
- Re-rendering the preview at higher resolution when zoomed. The preview is 1600 px on the long
  edge; export renders at full resolution.
- Localisation: strings are inline English, not yet in a String Catalog.
- App icon artwork. The asset catalog slot is empty.

## Recipe import (image / text)
- **On-device OCR (Vision) reliability.** It reads card layouts well, but sometimes skips an isolated single character such as a lone "0". Those fields are flagged "Not read — check" and left unset. The parser never guesses them.
  - An enlarged-crop retry is attempted.
  - A drawn-text-anchor trick was tried and removed because it didn't help.
- **Layout coverage.** The on-device parser handles "value above label" cards and "Key: Value" text. Other layouts need **Extract with AI**.
- **Test fixtures** are OCR *text* from two third-party cards, with credits anonymized. The card images themselves are not in the repo.

## Web showcase & AI extraction
- **AI extraction has not been run live.** This build machine has no Anthropic credentials. The request type-checks against `@anthropic-ai/sdk` 1.3.0, the response mapping is unit-tested, and the missing-key path was checked against a running server.
- **Docker image not built locally.** The Docker daemon wasn't running. The standalone production build was built and smoke-tested with `node server.js`:
  - pages, health check, the publish → cover → export → unpublish → delete cycle, auth, and path-traversal rejection;
  - a Swift-client ↔ server round trip.
- **The browser preview** ports the app's LUT, white balance, exposure and grain (parity-tested). It does **not** simulate clarity, sharpness or noise reduction.
- **SQLite means a single replica.** Back up the `/app/data` volume.
