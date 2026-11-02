# FilmLab

FilmLab is a recipe studio for FUJIFILM **X‑Trans IV and X‑Trans V** cameras. It runs on iPhone
(iOS 17+, SwiftUI) and is a working name. The X‑T30 III is the reference body: the only one with
manual-checked ranges and (experimental) USB slot access. Other bodies are profiled from community
reports. See `docs/cameras.md`.

**Preview → Tune → Compare → Save → (optionally) Write to camera.** Previewing never touches the
camera.

- **Studio.** Pick a photo from Photos or Files (JPEG, HEIF, RAF where Apple can decode it). Tap
  any of the 20 film simulations, tune every recipe setting, and see the preview update
  immediately.
  - Hold to see the Original, drag the split view, or pinch to zoom.
  - The histogram is computed from the displayed pixels.
  - Compare 4 or 9 recipes in a grid.
  - Save, duplicate, or export an approximate JPEG.
  - Every preview is labelled **Approximate · On-device**.
- **Cameras.** Pick *My camera* in Settings from 17 bodies (X‑Trans V: X‑T30 III, X‑M5, X‑S20, X‑T50,
  X‑E5, X100VI, X‑T5, X‑H2, X‑H2S; X‑Trans IV: X‑T30 II, X‑T4, X‑S10, X‑E4, X100V, X‑Pro3, X‑T3, X‑T30).
  - Studio, Tune and compatibility checks follow that body.
  - Recipes carry an optional X‑Trans IV/V tag.
  - Each recipe shows how it fares on every camera.
- **Explore and Library.**
  - 12 original FilmLab starter recipes, with search and filters (type, mood, simulation, X‑Trans generation, works on my camera).
  - Favourites, bulk export/delete, versioned JSON import/export, and provenance on every recipe.
- **Sets.** Seven-slot arrangements for C1–C7, with reordering, preview in Compare, and
  slot-by-slot install.
- **Import from Image or Text.** Bring in a recipe from a screenshot, a recipe card, a photo of notes, or pasted text (e.g. a Reddit comment).
  - On-device Vision OCR and a tested parser read it first: free, offline and private.
  - **Extract with AI** sends it to your FilmLab web server, which asks Claude to read unusual layouts.
  - Every field is reviewed before saving. Unread fields are flagged, never guessed.
  - Then *Preview & Adjust in Studio* or *Save to Library*.
- **Web showcase** (`web/`): a Next.js + shadcn site and API (SQLite), deployable on Dokploy. It provides:
  - recipe pages with an approximate in-browser preview;
  - an admin with AI import;
  - *Publish to Web* from the app.

  See `web/README.md`.
- **Camera.**
  - Demo camera, or USB via ImageCaptureCore (experimental).
  - Connected bodies are recognised from the catalog. Only the X‑T30 III gets slot access; other recognised bodies are *profile only*.
  - Model/firmware view, capability and verification view, read C1–C7, local backups and export.
  - Guarded single-slot writes: backup first, per-setting diff, explicit acknowledgement,
    read-back verification, and honest *outcome unknown* on interruption.
  - Redacted diagnostics.

> ⚠️ **Hardware status:** nothing has been verified on a real iPhone + X‑T30 III yet.
> - USB slot writes are off by default.
> - **Render with Camera** is disabled on real hardware until `docs/ptp-validation.md` P5 passes.
>
> FilmLab is not affiliated with FUJIFILM. Film simulation names are FUJIFILM trademarks, used
> descriptively.

## Build and run (Xcode 16+)

```sh
brew install xcodegen          # once
xcodegen generate              # creates FilmLab.xcodeproj from project.yml
open FilmLab.xcodeproj         # run the "FilmLab" scheme on an iPhone simulator or device

# command line
xcodebuild -project FilmLab.xcodeproj -scheme FilmLab \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

To build for a device, set `DEVELOPMENT_TEAM` in `project.yml` (or in Xcode), then run
`xcodegen generate` again.

Launch arguments for testing:

| Argument | Effect |
|---|---|
| `-uiTesting` | Temporary storage and fresh defaults |
| `-demoCamera` | Connects the in-memory demo camera on launch |

## Without Xcode (Command Line Tools only)

```sh
./scripts/typecheck.sh                              # type-checks all sources against the macOS SDK
./scripts/typecheck.sh -strict-concurrency=complete
./scripts/test-cli.sh                               # builds and runs all Swift Testing unit tests on macOS
FILMLAB_RECORD_GOLDEN=1 ./scripts/test-cli.sh       # re-record golden-image fixtures after an intentional engine change
```

## Docs

- `docs/research.md`: sourced facts, each tagged DOC / 3P / DEV / NV
- `docs/architecture.md`: modules, the pipeline order, the camera stack and its state machines
- `docs/cameras.md`: supported bodies, X‑Trans IV/V, recognition, compatibility, verification status (catalog: `shared/camera-catalog.json`)
- `docs/ptp-validation.md`: ordered hardware checks P1–P7 and a results log
- `docs/device-test-matrix.md`: manual tests on real devices
- `docs/known-limitations.md`: blockers and unverified assumptions

## Licensing notes

- All code is original to this project.
- Protocol facts are cited from ILFforever/fujifilm-ptp-recipes (docs CC BY 4.0) and
  beudbeud/reshipi (MIT). No code was copied from either.
- Demo photos are generated at runtime. No third-party images are included.
