# FilmLab

FilmLab is a recipe studio for the FUJIFILM X‑T30 III. It runs on iPhone (iOS 17+, SwiftUI) and is
a working name.

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
- **Explore and Library.**
  - 12 original FilmLab starter recipes, with search and filters (type, mood, simulation).
  - Favourites, bulk export/delete, versioned JSON import/export, and provenance on every recipe.
- **Sets.** Seven-slot arrangements for C1–C7, with reordering, preview in Compare, and
  slot-by-slot install.
- **Camera.**
  - Demo camera, or USB via ImageCaptureCore (experimental).
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
- `docs/ptp-validation.md`: ordered hardware checks P1–P7 and a results log
- `docs/device-test-matrix.md`: manual tests on real devices
- `docs/known-limitations.md`: blockers and unverified assumptions

## Licensing notes

- All code is original to this project.
- Protocol facts are cited from ILFforever/fujifilm-ptp-recipes (docs CC BY 4.0) and
  beudbeud/reshipi (MIT). No code was copied from either.
- Demo photos are generated at runtime. No third-party images are included.
