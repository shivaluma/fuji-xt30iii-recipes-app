# FilmLab Architecture

## Layers

```text
FilmLab/
  App/            FilmLabApp (@main), AppEnvironment (DI container), RootView, AppSettings, LibraryStore
  Features/       SwiftUI screens + @Observable @MainActor models
    Studio/       StudioModel, StudioView, PreviewCanvas, AdjustmentPanel, CompareGridView, SaveRecipeSheet
    Explore/      ExploreView, RecipeDetailView
    Library/      LibraryView, SettingsView, RecipeExportFile
    Camera/       CameraController (state machine), CameraView, SendToCameraSheet, SlotDetail, Capabilities
    Sets/         SetsListView, SetEditorView, SetInstallSheet
  Domain/         Pure value types — no frameworks beyond Foundation/CryptoKit
    Recipe/       FilmSimulation, RecipeField, RecipeSettings, FilmRecipe, RecipeSet
    Camera/       CameraSlot, CameraProfile (+RecipeValidator), CameraSlotSnapshot, SlotDiff, backups
    Rendering/    PreviewFidelity, PhotoAsset, RenderCacheKey, RenderedPreview
  Services/
    Storage/      LibraryPersistence (versioned JSON + migrations), RecipeTransfer. No bundled recipes:
                  the catalogue is the website (Web/WebRecipeFeed); LibraryStore removes leftover
                  unedited starters from earlier builds once.
    Imports/      PhotoImporter (immutable originals), DemoImageFactory (Mt Fuji sample photo + synthetic test images)
    Preview/      FilmLookEngine, FilmLookProfiles/FilmLUTBuilder, OfflinePreviewRenderer, caches, Histogram
    CameraPTP/    PTPCore, PTPSession, FujiRecipeCodec, CameraTransport, SimulatedFujiCamera, ImageCaptureAdapter
    CameraRAW/    CameraRenderService (+ Unvalidated / Demo implementations, JPEG validator)
    Web/          FilmLabWebClient (admin: AI extraction, publish), WebRecipeFeed (public GET /api/recipes → Explore, cached)
  SharedUI/       Theme tokens, platform shims, components (FidelityBadge, HistogramView, …)
  Resources/      Asset catalog and the Mt Fuji sample photo (by the project owner). No third-party photos.
FilmLabTests/     Swift Testing unit/integration tests (+ Fixtures/golden-*.json, Fixtures/TestRecipes.swift)
FilmLabUITests/   XCUITest acceptance flows (offline; the catalogue comes from FILMLAB_WEB_RECIPES_JSON)
```

The app uses MVVM with `@Observable` (iOS 17) models isolated to `@MainActor`. Long-running work
goes to actors:

- `OfflinePreviewRenderer` owns Core Image.
- `PTPSession` and `FujiPTPCameraTransport` own camera I/O.

Dependencies are injected through `AppEnvironment`. `-uiTesting` swaps in temporary storage, and
`-demoCamera` connects the emulator.

### Why JSON instead of SwiftData

The spec suggested SwiftData. FilmLab uses versioned Codable JSON (`LibraryDocument`, schema v1)
for four reasons:

- the library is small;
- the recipe exchange format must be stable JSON anyway, so one schema serves both;
- migrations are explicit, testable functions (`LibraryPersistence.migrate`);
- the domain types stay plain structs that can be tested on any toolchain.

A newer-schema file is never overwritten; the library opens read-only. A corrupt file is moved
aside, not deleted. Swapping in SwiftData later only touches `LibraryStore`.

## Design system (`SharedUI/Theme.swift`, `SharedUI/DesignSystem.swift`)

The minimum is iOS 17; the app is built and tuned with the iOS 27 SDK (iPhone 18 Pro).

- **Chrome is native.** A system `TabView`, navigation bars with large titles and toolbars,
  `.searchable`, and system sheets. On iOS 26+ they render as **Liquid Glass**, the tab bar
  collapses while scrolling, and titles get a subtitle line. No `UINavigationBar` appearance
  overrides: they would turn off the glass bar and its scroll-edge effect.
- **Controls** use glass button styles on iOS 26+ (`.glass` / `.glassProminent`) and fall back to
  `.bordered` / `.borderedProminent` capsules on iOS 17–25. The helpers in `Theme.swift`
  (`primaryActionStyle`, `secondaryActionStyle`, `chipStyle`, `floatingCapsule`,
  `GlassButtonShape`) hold every availability check, so feature code has no `#available`.
  Glass code sits behind `#if compiler(>=6.2)` so `scripts/typecheck.sh` still builds with older
  Command Line Tools SDKs (they compile the fallback).
- **Colour.** Light mode keeps the website's palette (white page, warm grey `#f3f3f1` panels,
  ink `#0c0c0c` for primary actions and selection). Every token has a Dark Mode value; the
  accent flips to paper-white with ink text. Pills over photos ignore the appearance because
  they sit on the image.

| Component | Used for |
|---|---|
| `SectionHeader` | Bold title + subtitle + an `ArrowLink` ("See all ›") |
| `CircleIconButton` | Round glass button (the Tune −/+ stepper); `isOn` makes it prominent |
| `PillChip` / `FilterChip` | Glass capsule chips; the selected chip is prominent (ink) |
| `PhotoRecipeCard` | 4:3 rounded photo card with an "Approximate" pill, an X-Trans tag and a status pill. The status pill shows only real state (In Library or Favorite), never invented counts. Grid cells use a compact variant with one pill. |
| `PhotoPill` / `FidelityBadge` | Clear (or dark-tinted) glass capsules laid over photos |
| `TunePanel` / `ParameterCard` | Horizontal parameter cards: grey, or ink when selected, each with a thin strip of its colour (COLOR is a rainbow). Below them is a large −/+ stepper with VoiceOver adjustable actions. Every step is clamped to the profile's range, and inapplicable cards are dimmed with a reason. |
| `DestinationCard` | DESTINATION eyebrow, a slot row ("C1", name, simulation, picker chevron) and a full-width prominent CTA. Used for "Review Changes for Cn" and then "Write to Cn" once acknowledged. |
| `PrimaryButton(Label)` / `SecondaryButtonLabel` | Full-width prominent / secondary actions; the label also styles `PhotosPicker` and `ShareLink` |

Names, layout details, content and iconography are FilmLab's own.

## Recipe model

- `RecipeField<T>` makes "not set", "not applicable" and a concrete 0/OFF distinct types. JSON
  encodes them as tagged objects (`{"state":"value","value":0}`).
- `RecipeSettings.normalized()` applies the manual's dependency rules:
  - Kelvin applies only with COLOR TEMPERATURE;
  - grain size is n/a when grain is OFF;
  - COLOR is n/a on B&W simulations;
  - MONOCHROMATIC COLOR applies to ACROS and MONOCHROME only;
  - DR, Highlight and Shadow are n/a when D RANGE PRIORITY ≠ OFF.

  A field that becomes applicable again becomes `unset`, never an invented value.
- `CameraProfile.xt30III` is the per-property capability map. Each property has a range or
  allowed values plus a `VerificationStatus` for its values and for PTP read/write.
  `RecipeValidator` explains every rejection.
- `fingerprint` is a SHA-256 of sorted-key JSON, used in cache keys.

## Offline pipeline (`FilmLookEngine`, version `filmlab-approx-1`)

The renderer always starts from the untouched source, so edits never accumulate.

1. **Decode and normalize.** ImageIO and Core Image read the file colour-managed (embedded ICC
   honoured) and apply EXIF orientation. RAF goes through `CIRAWFilter` and fails clearly if it is
   unsupported; there is no embedded-JPEG fallback. The renderer caches a bitmap working copy at
   preview size.
2. **Exposure and white balance**, in linear light: suggested EV, then `CITemperatureAndTint`
   relative to an assumed 5500 K source, then the R/B shift colour matrix.
3. **Stages 3–6** happen in one cached 3D LUT (25³, sRGB-encoded domain, `FilmLUTBuilder`):
   - tone curve (highlight/shadow, DR highlight protection, DRP shadow lift);
   - base profile (contrast, hue bands, split tone, fade);
   - COLOR, Color Chrome and FX Blue;
   - monochrome mix, filter and toning.

   The LUT key holds only what affects it, so cubes are reused across slider moves.
4. **Clarity, sharpness and NR**, with size-relative radii so thumbnails and exports match:
   - clarity is a large-radius unsharp mask;
   - sharpness uses luminance sharpening;
   - negative sharpness is a slight blur;
   - positive NR uses `CINoiseReduction`.
5. **Grain**: deterministic, luminance-only, multiplicative in linear light, and size-relative.
   The noise comes from the generator's *alpha* channel, because `CIColorMatrix` un-premultiplies
   its input. This bug was found by a unit test, measured, and fixed.
6. **Output**: `CIContext.createCGImage` into an explicit colour space (Display P3 in the app,
   sRGB in tests). The colour space is part of the cache key.

### Profiles are placeholders

Every simulation has a hand-written `FilmLookProfile` built for FilmLab. These are not derived
from Fujifilm data and not calibrated. The UI badge, the Settings › About text, the export sheet
and `known-limitations.md` all say so.

### Calibration (future)

1. Shoot a ColorChecker-style target, saved as RAW plus PROVIA, on the X‑T30 III.
2. For each simulation, process the RAF in camera (or X RAW STUDIO) with only the simulation
   changed.
3. Fit a 3D LUT from the neutral render to each simulation's render.
4. Report the residual ΔE2000 per patch.
5. Ship the LUT as `FilmLookProfile` data, versioned with a new engine version string so every
   cache invalidates.

This remains an approximation with measured limits. Local tone operators (DR, clarity) and grain
cannot be captured by a global LUT.

### Interactivity and caches

- `StudioModel.scheduleRender` debounces by 35 ms, cancels the previous task, and stamps a
  `generation`. A result is shown only if its generation is still current. Tests cover 25 rapid
  edits.
- The compare grid has its own generation and cancellation. Every cell uses the same source,
  size and crop.
- The memory LRU (80 renders) is keyed by `RenderCacheKey`: source fingerprint, settings
  fingerprint, engine version, long edge, colour space, fidelity and processing identity.
- The disk JPEG cache holds renders ≤ 800 px, with an LRU byte limit of 200 MB. It is
  invalidated per source when a photo is removed.

## Camera stack

```text
CameraController (@MainActor state machine, guarded flows)
  └─ CameraTransport (protocol)
       └─ FujiPTPCameraTransport (actor; operation gate: select-slot + N properties never interleave)
            └─ PTPSession (actor; transaction IDs, response validation, timeouts, redacted log, FIFO gate)
                 └─ PTPCommandChannel (protocol)
                      ├─ ImageCapturePTPChannel (@MainActor; ICCameraDevice.requestSendPTPCommand)
                      └─ SimulatedFujiCamera (actor; demo + tests, with fault injection)
```

The demo and the tests run the **same** session, codec, read/write and verification code as the
real USB path. Only the channel differs.

### Write state machine (single slot)

```text
chooseSlot → preparing (fresh read; backup of all 7 slots if none this session)
          → review (per-setting diff: changed / unchanged / keeps camera value / n/a; validation)
          → [acknowledge toggle + explicit "Write to Cn"]
          → writing (select slot → properties in ILF order → name)
          → read-back → verified | mismatched(exact bytes) | failed | unknown
```

- `unset` fields are never written, so the camera keeps its value, and the diff says so.
- Disputed or unknown properties are never written; they stay in backups byte-for-byte.
- If the transport fails *after* the first property write, the result is `outcomeUnknown`. The slot
  goes into `slotsNeedingVerification` and is re-read automatically on reconnect.
- There is no rollback claim anywhere.

### Set install

Writes run sequentially, one plan per slot, each with its own outcome. **Stop** finishes the
current slot, then marks the rest `stopped`. **Install Remaining** resumes. An `unknown` outcome
stops the run. The install is not atomic.

### Camera rendering

`CameraRenderService` has three implementations:

- `UnvalidatedCameraRenderService`: always "not validated" on real hardware.
- `DemoCameraRenderService`: uses the approximate engine, labelled *Demo · Simulated camera*.
- `AuthenticJPEGValidator`: SOI/EOI markers, ImageIO type, decodability. Nothing may be labelled
  `.authenticCamera` without passing it.

### Privacy and observability

- The serial number is never stored; only a salted SHA-256 prefix is kept.
- The PTP log records opcode, parameters, byte counts, response code and duration. It never
  records payloads.
- Diagnostics are shared only through an explicit share sheet.
- `os.Logger` uses `.public` only for model and firmware strings.
