# PTP Validation Plan & Evidence

**Status: not started on hardware.** No PTP traffic has been exchanged with a real X‑T30 III.
Everything in `FujiRecipeCodec` is **third-party-reported** (see `research.md` §3).

## Evidence so far

| Item | Evidence | Status |
|---|---|---|
| Container encode/decode, malformed input, fuzzing | `PTPCoreTests`: 7 tests, including 3000 random-byte inputs | ✅ unit-tested |
| Session: response codes, TID mismatch, timeout, one transaction in flight | `PTPSessionTests` | ✅ unit-tested |
| Codec: ×10 tone, NR table, grain/WB/sim codes, write order, DRP gating, round-trip | `FujiCodecTests` | ✅ unit-tested against **our reading** of the sources |
| Read/write/verify/disconnect flows | `TransportTests` and `CameraFlowTests` on `SimulatedFujiCamera` | ✅ emulator only, which is not evidence about real hardware |
| ImageCaptureCore discovery on iPhone | — | ⛔ needs an iPhone, an X‑T30 III and Xcode |
| Pass-through buffer order and format on iOS | — | ⛔ |
| Every Fujifilm property code and encoding on the X‑T30 III | — | ⛔ |

## Checks, in order

Each check has an ID. Record the result (pass/fail, firmware, iOS version, date, redacted log
excerpt) in the table at the bottom. Do not start a check until the previous one passes.

### P1 — Discovery (read-only)
- Camera at fw ≥ 1.10, CONNECTION MODE = USB RAW CONV./BACKUP RESTORE, USB-C data cable.
- Camera tab › Connect via USB.
- Expect: control-authorization prompt → `found` event → `requestOpenSession` succeeds.
- Record `device.name` and whether `capabilities` contains `ICDeviceCapability.cameraDeviceCanAcceptPTPCommands`.
- Repeat with the wrong USB mode and with a charge-only cable. Record what the app shows.

### P2 — Harmless read
- Expect GetDeviceInfo (0x1001) to decode: manufacturer `FUJIFILM`, model `X-T30 III`, firmware.
- Check `ImageCapturePTPChannel.observedSwappedBuffers == false`. If it is `true`, the buffer order
  differs from Apple's sample; record it.
- Confirm 0xD18C is listed in `devicePropertiesSupported`. If it isn't, check the USB mode.
- Disconnect, reconnect, and repeat 3× (clean reconnect).

### P3 — Read C1–C7
- Before reading, write each slot's settings down from the camera menu (EDIT/CHECK).
- Read All Slots. Compare every decoded field with your notes. **Record every mismatch per
  property code.**
- Check `unknownValues` for codes FilmLab doesn't decode.
- Check that the selected slot is restored afterwards (SELECT CUSTOM SETTING unchanged).
- Unplug, replug, read again. Raw bytes must be identical.

### P4 — Model round-trip
- Feed the raw bytes from P3 into the `FujiRecipeCodec.decode` → `encode` unit tests as new
  fixtures (add them under `FilmLabTests/Fixtures/`).

### P5 — Authentic RAW render (keep the feature disabled until this passes)
- Back up all slots, and note the camera menu state for C1–C7 by hand.
- Implement reshipi's reported sequence (0x900C / 0x900D / 0xD185 / 0xD183) behind a
  developer-only flag.
- Convert one X‑T30 III RAF.
- Compare against X RAW STUDIO 1.28+ output from the same RAF and settings (visual + EXIF).
- **Re-read C1–C7 and compare byte-for-byte with the backup. Any difference fails this check.**
- Confirm the source RAF hash is unchanged.
- Only then implement a validated `CameraRenderService` that returns `.authenticCamera` (after
  `AuthenticJPEGValidator`).

### P6 — Single-slot write (sacrificial slot only, with explicit consent)
- Use **C7**, with a backup taken.
- Enable Settings › Experimental camera slot writes (type ENABLE).
- Write a recipe that changes one property (e.g. Shadow +1). Expect `verified`.
- Then change one property per family (sim, grain, CC, FXB, WB+Kelvin, shifts, tone, color,
  sharpness, NR, clarity, mono WC/MG, name).
- For each family, compare the camera menu with the app's read-back.
- Test D RANGE PRIORITY ≠ OFF and confirm DR/tone writes are skipped (and whether DRP is stored at all).
- Test grain OFF and confirm the read-back is 6/7 (equivalence accepted).
- Resolve the name-first vs name-last disagreement: try both on C7 and record which persists.
- Interrupt a write (unplug mid-write). Expect `outcomeUnknown`, then re-read on reconnect.

### P7 — Set install
- Install a 2-slot Set on C6–C7. Press Stop after the first slot. Resume. Verify both.

## Results log

| Check | Date | iPhone / iOS | Camera fw | Result | Notes / redacted log |
|---|---|---|---|---|---|
| P1 | | | | | |
| P2 | | | | | |
| P3 | | | | | |
| P4 | | | | | |
| P5 | | | | | |
| P6 | | | | | |
| P7 | | | | | |
