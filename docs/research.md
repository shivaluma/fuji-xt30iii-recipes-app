# FilmLab — Research Log

Research done 2026‑11‑02, before any camera-specific code was written. Each capability is
tagged with one of:

| Tag | Meaning |
|---|---|
| **DOC** | Verified in Apple or Fujifilm documentation |
| **3P** | Reported by a third party (community reverse engineering or another app) |
| **DEV** | Verified on our physical X‑T30 III |
| **NV** | Not verified |

> **No row is tagged DEV yet.** We had no iPhone, no X‑T30 III and no Xcode while building this
> (see `device-test-matrix.md`).

## 1. Sources consulted

| # | Source | Used for |
|---|---|---|
| 1 | https://fujirecipestudio.com/ | Product workflows only: Discover → Library → Studio → write a slot or a Set. FilmLab copies none of its visual identity or code. |
| 2 | X‑T30 III manual, IMAGE QUALITY SETTING: https://app.fujifilm-dsc.com/en/manual/x-t30-iii/menu_shooting/image_quality_setting/index.html | Values, ranges, C1–C7, FS1–FS3 |
| 3 | X‑T30 III manual, USB RAW conversion: https://app.fujifilm-dsc.com/en/manual/x-t30-iii/connections/raw/index.html | USB RAW CONV./BACKUP RESTORE mode |
| 4 | X RAW STUDIO: https://www.fujifilm-x.com/en-us/support/download/software/x-raw-studio/ | Camera-side RAW conversion; X‑T30 III support |
| 5 | ImageCaptureCore: https://developer.apple.com/documentation/imagecapturecore, plus the SDK headers | Discovery, sessions, authorization |
| 6 | `ICCameraDevice.requestSendPTPCommand(_:outData:completion:)`, plus Apple's archived PTPPassThrough sample | PTP pass-through format |
| 7 | CIRAWFilter, and Apple's RAW support list: https://support.apple.com/en-us/122870 | RAF decoding on iOS |
| 8 | ILFforever/fujifilm-ptp-recipes (`main` @ daba2d9, 2026‑09‑04): docs/protocol.md, docs/properties.md, reverse-engineering notes | Property codes, encodings, read/write flow |
| 9 | beudbeud/reshipi (`main` @ ef6b3cd, 2026‑08‑17): `Ptp.kt`, `FujiCamera.kt`, `RecipePreset.kt`, `THIRD_PARTY.md` | Property codes, reported X‑T30 III validation, RAW conversion sequence |

## 2. Camera facts (X‑T30 III)

| Capability | Finding | Tag | Source |
|---|---|---|---|
| Sensor / processor | 26.1 MP BSI X‑Trans CMOS 4 + X‑Processor 5 | DOC | product page, spec page |
| Firmware | 1.10 (2026‑06‑04) is the latest. 1.01 changed LCD tone. Neither changes image-quality settings. | DOC | Fujifilm firmware page |
| Film simulations | PROVIA/STANDARD, Velvia/VIVID, ASTIA/SOFT, CLASSIC CHROME, REALA ACE, PRO Neg. Hi, PRO Neg. Std, CLASSIC Neg., NOSTALGIC Neg., ETERNA/CINEMA, ETERNA BLEACH BYPASS, ACROS (+Ye/R/G), MONOCHROME (+Ye/R/G), SEPIA. AUTO exists only with the AUTO lever. | DOC | [2] |
| Grain | Roughness: STRONG / WEAK / OFF. Size: LARGE / SMALL. | DOC | [2] |
| Color Chrome, FX Blue | STRONG / WEAK / OFF | DOC | [2] |
| White balance | WHITE PRIORITY, AUTO, AMBIENCE PRIORITY, CUSTOM 1–3, COLOR TEMPERATURE, DAYLIGHT, SHADE, FLUORESCENT 1–3, INCANDESCENT, UNDERWATER | DOC | [2] |
| Kelvin | 2500–10000 K, 10 K dial steps | DOC | [2] |
| WB shift R/B | Range −9…+9 | 3P (the manual shows only a grid) | [8], [9] |
| Dynamic range | AUTO / 100 / 200 / 400. DR200 needs ISO 320+, DR400 needs ISO 640+. | DOC | [2] |
| D Range Priority | AUTO / STRONG / WEAK / OFF. Any value except OFF adjusts DR and the tone curve automatically. | DOC | [2] |
| Highlight / Shadow | −2…+4 | DOC | [2] |
| Highlight / Shadow half steps | Wire format is value × 10, and one example uses −1.5 | 3P | [8] |
| Color, Sharpness, High ISO NR | −4…+4, step 1 | DOC | [2] |
| Clarity | −5…+5. Non-zero values slow saving. HEIF disables it. | DOC | [2] |
| Monochromatic color WC/MG | ACROS and MONOCHROME only (DOC). Range −18…+18, from the wire format (×10, ±180). | DOC (applicability) + 3P (range) | [2], [8] |
| Smooth skin | **Not present.** The body has PORTRAIT ENHANCER instead. | DOC | [2] |
| Default values | Not stated in the manual | NV | — |
| C1–C7 | Created through EDIT/SAVE CUSTOM SETTING and recalled through SELECT CUSTOM SETTING. They can be renamed. | DOC | [2] |
| C-slot name limit | 25 characters, limited ASCII | 3P (the manual states no limit) | [8] |
| C-slot film simulation | A film simulation saved in a C bank applies only when the dial is set to **C** | DOC | [2], parts page |
| FS1–FS3 | Film simulation dial positions. With FS RECIPE = ON they hold separately registered image-quality items, with separate still and movie settings. Not applied with the AUTO lever. **They are not C slots.** | DOC | [2] |
| USB mode | USB POWER SUPPLY/COMM SETTING = AUTO or POWER SUPPLY OFF/COMM ON, then CONNECTION MODE = USB RAW CONV./BACKUP RESTORE. The manual describes this mode for computers only, not phones. | DOC | [3] |
| Camera-side RAW conversion | X RAW STUDIO uses "the camera's image processing engine". Version 1.28.0 (2025‑10‑23) added the X‑T30 III. | DOC | [4] |
| Third-party app support | Fuji Recipe Studio lists the X‑T30 III as verified, as an iOS 17+ USB public beta | 3P | [1] |

## 3. PTP protocol facts

| Capability | Finding | Tag | Source |
|---|---|---|---|
| Container format | u32 length (including the 12-byte header), u16 type (1 = cmd, 2 = data, 3 = resp, 4 = event), u16 code, u32 transaction ID, then params or payload. Little-endian. | DOC (ISO 15740) / 3P | [8] |
| Standard operations | 0x1001 GetDeviceInfo, 0x1002 OpenSession, 0x1003 CloseSession, 0x1014 GetDevicePropDesc, 0x1015 GetDevicePropValue, 0x1016 SetDevicePropValue | DOC (ISO) | [8], [9] |
| Preset access | Slot selector 0xD18C (1…7), name 0xD18D (PTP string), properties 0xD18E…0xD1A4 through standard Get/SetDevicePropValue. "There is no secret Fuji opcode" for properties. | 3P | [8], [9] |
| Value encodings | See `FujiRecipeCodec.swift`. The two sources agree on film simulation, grain, CC/FXB, WB, shifts, Kelvin, tone ×10 and the NR lookup. | 3P | [8], [9] |
| Disputed codes | 0xD18E, 0xD18F, 0xD1A3, 0xD1A4 and 0xD1A5 mean different things in each source. FilmLab **reads and preserves** them and **never writes** them. | 3P (conflicting) | [8], [9] |
| DR Priority side effects | While DRP ≠ OFF, writes to DR, Highlight and Shadow are rejected with 0x201C, and DR reads back as 0xFFFF | 3P | [8] |
| DR AUTO / DRP storage | reshipi says presets "can't store DR Auto" and that DRP is "not stored in camera presets". ILF lists DRP codes. **Conflict.** | 3P (conflicting) | [8], [9] |
| Grain read-back | The X‑T30 III reads a written 1 (OFF) back as 6 or 7 | 3P | [9] |
| Write order | ILF: film sim → DRP → DR → effects → WB/Kelvin/shift → tone → name **last**. reshipi: name **first**. FilmLab follows ILF. | 3P (conflicting) | [8], [9] |
| Silent failures | "A camera can return OK without applying a value", so FilmLab reads back after every write | 3P | [8] |
| Session collision | Response 0x201E (already open): close and retry once | 3P | [9] |
| RAW conversion | reshipi's sequence: vendor op 0x900C (SendObjectInfo, format 0xF802), 0x900D (SendObject), poll profile property 0xD185, patch it, set 0xD185, trigger with 0xD183 = 0, then poll GetObjectHandles, GetObject, DeleteObject. ILF calls this "untraced", says 0xD185 is unused by the SDK, and documents no vendor opcodes. **Conflict, and nobody shows that C1–C7 stay unchanged.** | 3P (conflicting) | [8], [9] |
| Warranty | ILF: "Using this protocol may void your Fujifilm manufacturer warranty." | 3P | [8] |
| Tested bodies | ILF: X‑H2 fw 5.20 and X‑T5 fw 4.20 only (**not** the X‑T30 III). reshipi: "Validated on the X‑T30 III" (2026‑08). | 3P | [8], [9] |

Licences: the ILF documentation is CC BY 4.0 and its example code is MIT. reshipi is MIT
© 2026 Adrien Beudin, and its PTP layer is "derived from FilmKit (MIT)". The FilmKit URL differs
between reshipi's `THIRD_PARTY.md` and its source comments, so it is unresolved.
**FilmLab contains no code copied from either repository.** It re-implements the documented
facts and cites them. reshipi's bundled donor RAF has unclear rights and was **not** used.

## 4. Apple platform facts

| Capability | Finding | Tag | Source |
|---|---|---|---|
| `ICDeviceBrowser`, `ICCameraDevice` | Available on iOS 13+ | DOC | SDK headers |
| `browsedDeviceTypeMask` | Available on iOS 15.2+ | DOC | SDK headers |
| `requestSendPTPCommand(_:outData:completion:)` | iOS 13+. The completion delivers `(responseData, ptpResponseData, error)`. | DOC | SDK header `ICCameraDevice.h` |
| Pass-through buffer format | The command is a full container, and ICC ignores our transaction ID. outData is the raw payload. The data-in buffer has no header. The response buffer **includes** its 12-byte header. | DOC (sample code) / **NV on iOS** | PTPPassThrough sample |
| PTP capability check | `capabilities` contains `ICCameraDeviceCanAcceptPTPCommands` ("All PTP cameras have this capability") | DOC | header |
| Authorization | `requestControlAuthorization` and `requestContentsAuthorization` (iOS 14+, unavailable on macOS) | DOC | `ICDeviceBrowser.h` |
| Info.plist | Apple says tethering from an iOS app needs `NSCameraUsageDescription`. `com.apple.security.device.usb` is macOS-only. | DOC | [5] |
| USB camera on iPhone | Not stated explicitly by Apple. One forum thread reports a Canon not detected, with no resolution. | **NV** | developer forums 751312 |
| outData latency | One developer reported multi-second timeouts on some cameras for commands with outData | 3P | developer forums 798202 |
| CIRAWFilter | iOS 15+. `supportedCameraModels` is available at runtime. Apple's iOS 26 RAW list includes the **FUJIFILM X‑T30 III**. Compressed-RAF support is not stated. | DOC (model list) / NV (compressed RAF) | [7] |

## 5. What this means for the design

1. **Preview is local and approximate.** Nothing in the documentation lets an iPhone reproduce
   Fujifilm's rendering, so the offline engine is labelled *Approximate · On-device* everywhere.
2. **Camera rendering is disabled** until we prove on a device that it leaves C1–C7 unchanged.
   The sources conflict and nobody demonstrates that, and the hard constraint says to disable
   rather than risk it.
3. **Reads are allowed, and writes are opt-in with heavy guards.** Every guard is backed by a
   3P warning: read-back after every write, never write disputed codes, back up first.
4. **C1–C7 ≠ FS1–FS3**, as the manual states. FilmLab only addresses C slots.
5. **Support is modelled per property** (`CameraProfile`), each with its own `VerificationStatus`.
