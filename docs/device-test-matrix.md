# Real-Device Test Matrix

Run this manually. Fill in every row. A feature may be **enabled by default** only after its rows
pass on real hardware.

**Environment used so far:** a Mac with Command Line Tools only (no Xcode, no simulator, no
iPhone, no camera). Nothing below has been run.

| # | Scenario | Steps | Expected | Result | Date | iPhone / iOS | Cam fw |
|---|---|---|---|---|---|---|---|
| D1 | Build & launch on simulator | `xcodegen generate`, then run the FilmLab scheme on an iPhone simulator | App launches. Studio shows a synthetic photo with the *Approximate · On-device* badge | | | | |
| D2 | Offline vertical slice | Photos › pick a JPEG and a HEIF; tap 5 simulations; drag sliders; press and hold; split view | Preview changes on every tap. *Original* is shown while held. No stalls | | | | |
| D3 | Compare grid | Compare › 3×3 › choose 9 › tap a cell | Same crop on every cell; tapping loads that recipe | | | | |
| D4 | Persistence | Save a recipe, force-quit, relaunch | The recipe is still in Library | | | | |
| D5 | Export / import | Export All › AirDrop to self › Import | Merge summary appears and nothing is overwritten | | | | |
| D6 | RAF via Files | Import an X‑T30 III RAF (compressed and uncompressed) | Decodes, labelled *Original (Apple RAW decode)*, or a clear unsupported message | | | | |
| D7 | Performance | 26 MP JPEG: slider scrub, Instruments Time Profiler + Allocations | Record ms per render, peak memory, dropped frames. **Set SLAs from these numbers.** | | | | |
| D8 | VoiceOver / Dynamic Type | Run Studio and Camera flows with VoiceOver and the largest text size | Every control is labelled; the divider is adjustable | | | | |
| H1 | USB discovery | `ptp-validation.md` P1 | | | | | |
| H2 | Harmless read / reconnect | P2 | | | | | |
| H3 | Read C1–C7 and back up | P3; unplug and replug; read again | Stable snapshots | | | | |
| H4 | Wrong mode / bad cable | Wrong CONNECTION MODE; charge-only cable | *Wrong USB mode* or nothing found, plus guidance | | | | |
| H5 | Busy / low battery | Read while the camera is reviewing images; read with the battery <10% | *Busy* plus retry; no crash | | | | |
| H6 | Authentic render | P5 | JPEG matches the camera; C1–C7 byte-identical afterwards; RAF unchanged | | | | |
| H7 | Incompatible RAF | RAF from another body | Explicit "not compatible" message | | | | |
| H8 | Slot write (sacrificial) | P6 | Verified, or exact mismatches | | | | |
| H9 | Interrupted write | Unplug mid-write | *Outcome unknown*; auto re-read on reconnect | | | | |
| H10 | Set install, stop and resume | P7 | Outcome per slot; no false "all done" | | | | |
