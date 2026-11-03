# Wireless: Bluetooth and Wi‑Fi

Research done 2026‑11‑03. Tags as in `research.md`: **DOC** (Fujifilm/Apple documentation),
**3P** (community reverse engineering or another app's claims), **NV** (not verified).
Nothing here has been checked on our own camera yet (see the checks at the end).

## What each radio carries

| Data | Bluetooth LE | Wi‑Fi | USB |
|---|---|---|---|
| Pairing, client identity | ✅ DOC/3P | — | — |
| Clock sync | ✅ DOC (XApp), 3P (protocol) | — | — |
| Location for geotags | ✅ DOC (SMARTPHONE LOCATION SYNC), 3P | — | — |
| Remote shutter | ✅ DOC, 3P | ✅ remote mode, 3P | — |
| Turn the camera's Wi‑Fi on | ✅ 3P (libfuji) | — | — |
| Photos (JPEG/HEIF, RAW per body) | ❌ DOC: XApp switches to Wi‑Fi | ✅ PTP/IP, 3P | ✅ |
| Live settings (film sim, WB, ISO…) | ❓ Huginn claims it, method unknown | ✅ XApp remote, DOC | ✅ |
| **C1–C7 recipes** | ❓ only via the settings backup file, format unpublished | ❓ no public report either way | ✅ 3P (reshipi, Fuji X Weekly app, FilmLab) |
| Settings backup / restore | ✅ 3P: file service, protocol unpublished | — | ✅ DOC (X Acquire), 3P |

## Bluetooth LE (what FilmLab implements)

Sources: gkoh/furble `lib/furble/Fujifilm*.{h,cpp}` @ 0cac22a (2026‑09‑13), including secure
pairing added after Fujifilm's July 2025 firmware (PR #212); petabyt/libfuji `lib/bluetooth.c`.
FUJIFILM manuals: X‑T30 III *Pairing with a smartphone* and *NETWORK/USB SETTING*. All 3P.

- **Advertising.** Manufacturer data starts with company ID `0x04D8`.
  - Older bodies: service `af854c2e…` or `117c4142…`, plus a 4‑byte token (type `0x02`).
  - Secure bodies: `a9d2b304…` while PAIRING REGISTRATION is open; `123d8f06…` with a 5‑byte
    serial when a paired phone may reconnect.
- **Pairing.**
  - Secure: bond (iOS shows a code, the camera shows the same code), read the 4‑byte status
    `f557d96b…`, write it back with byte 3 = `0x20`.
  - Legacy: write the advertised token to `aba356eb…`.
  - Then write the client name ("FilmLab") to `85b9163e…`.
- **Session.** Subscribe to the configuration/notification characteristics, write a 10 s
  geotag interval to `c95d91ae…`.
- **Clock.** When `f9150137…` notifies `02 00`, write `u16 year, month, day, hour, minute,
  second` (LE, local time) to `b9bfd37f…` (libfuji).
- **Location.** When `ad06c7b7…` notifies `01 00`, write lat/lon ×1e7, altitude (m), 4 pad
  bytes and the time (23 bytes, LE) to `0f36ec14…` (furble). Only if the user turned on
  *Share location for geotags*.
- **Shutter.** `7fcf49c6…`: `01 00` then `02 00` to press, `01 00` then `00 00` to release.

Code: `Services/CameraBLE/FujiBLEProtocol.swift` (pure, every byte unit-tested in
`BluetoothTests`), `FujiBluetooth.swift` (CoreBluetooth), `PhoneLocation.swift`.

### Deliberately not implemented

- **Settings backup / recipe writes over Bluetooth.** libfuji names a file service
  (`af854c2e…`: file info `c922ac69…` = 40‑byte name + u32 size, data `ac0c799a…`, an example
  `backup.dat` of ~33 KB), and tiredboffin/fffw reports unpublished tools that back up and
  restore it and edit C1–C7 inside it ("more or less stable across models"). The transfer
  protocol and the file layout are not public. Writing a guessed layout could scramble every
  setting on the camera, so FilmLab doesn't. Huginn (iOS, Sept 2026) claims wireless C1–C7
  writes; its method isn't disclosed.

## Wi‑Fi photo import (what FilmLab implements)

Sources (all 3P): petabyt/libfuji @41484e8 `lib/fuji.c`, `lib/fujiptp.h`, `lib/bluetooth.c`;
petabyt/camlib @f1c94c6; malc0mn/ptp-ip @992d64b `ip/packets_fuji.go`; petabyt/fudge @2078bf5.

- **Transport.** TCP to `192.168.0.1:55740` only (events and live view ports are for remote
  shooting). Not standard PTP/IP: an 82‑byte init packet (`0x52`, type 1, version `0x8F53E4F2`,
  fixed GUID, UTF‑16LE client name), then ordinary USB PTP containers on the same socket.
  Teardown: CloseSession, then `08 00 00 00 FF FF FF FF`.
- **Session (libfuji `fuji_setup`).** OpenSession (transaction 1) → poll `D212` until `DF00` ≠ 0
  (the user presses OK) → read `DF22/DF25/DF21/DF24` → set `DF01` ClientState (20 after a
  Bluetooth handoff, 5 with a remote version, else the camera's mode) → version handshake
  (echo `DF23`/`DF22`, or announce `DF24 = 0x2000C`) or, after a handoff, the XApp sequence
  (`DF28` echo, `D226/D227 = 0`, ops `0x9054/0x9055/0x9050/0x9053`, read `D620/D621`).
  Remote-shooting mode (`DF00 = 6`) is refused with an explanation.
- **Browsing.** Handles are 1…N (`D222`); FilmLab compares the first and last ObjectInfo to
  decide which end is newest. ObjectInfo always precedes GetThumb (newer firmware blocks
  otherwise).
- **Download.** `D227 = 1` (real sizes) → ObjectInfo → GetPartialObject in 1 MiB chunks
  streamed to disk → `D227 = 0`. After a Bluetooth handoff: `D226 = 2` before and after (NV:
  libfuji restores 2 afterwards; 1 = resized copy).
- **Bluetooth handoff.** Read SSID `bf6dc9cf…`, write `04 00` to `600655e6…`, read password
  `e809256a…`, wait for `a68e3f66…` byte 0 (1 ready, 0 busy). iOS joins the hidden WPA2
  network with `NEHotspotConfiguration` (join-once), when the app has the Hotspot
  Configuration capability; otherwise the user joins in Settings.

Why it's quicker than XApp's flow (by design; not measured against XApp yet): no Settings detour
after a Bluetooth handoff, connection retries every 0.4 s instead of fixed waits, on-screen and
newest thumbnails first, originals streamed in 1 MiB chunks and handed to Photos without
re-encoding while the next file downloads, already-imported files skipped.

Code: `Services/CameraWiFi/` — `FujiWiFiProtocol.swift` (pure), `FujiWiFiSession.swift`
(channel + session), `TCPStream.swift` (Network.framework, Wi‑Fi only, Nagle off),
`SimulatedWiFiCamera.swift` (a real TCP server on 127.0.0.1 used by tests and the in-app demo),
`CameraHotspot.swift`, `PhotoLibrarySaver.swift`; UI in `Features/Camera/WiFiImport*.swift`.
Tests: `FilmLabTests/WiFiTests.swift` runs the whole handshake and a chunked download over
real sockets.

Not done: RAW (RAF) over Wi‑Fi (libfuji: PC AutoSave only), remote shooting / live view,
background transfers.

## iOS notes

- `NSBluetoothAlwaysUsageDescription` and `NSLocationWhenInUseUsageDescription` are set in
  `project.yml`. Bluetooth runs while the app is in the foreground (no background mode yet).
- iOS owns the bond: removing it means Settings › Bluetooth › camera › Forget. FilmLab's
  *Forget* only clears its own record.
- The camera keeps one active phone (SELECT PAIRING DESTINATION). Using FilmLab and XApp on
  the same phone may need re-selecting the destination (NV).
- The iOS Simulator has no Bluetooth; the Camera tab says so. Wi‑Fi import can be tried there
  with the demo camera.
- Wi‑Fi needs `NSLocalNetworkUsageDescription` (iOS asks once) and saving needs
  `NSPhotoLibraryAddUsageDescription` (add-only). Joining the camera network from inside the
  app needs the **Hotspot Configuration** capability on the App ID (paid developer account):
  add `com.apple.developer.networking.HotspotConfiguration` to an entitlements file and set
  `CODE_SIGN_ENTITLEMENTS` in `project.yml`. Without it, FilmLab asks the user to join the
  FUJIFILM network in Settings and carries on.

## Hardware checks (do in order; record results in `ptp-validation.md`)

| ID | Check | Expect |
|---|---|---|
| B1 | Camera tab open, camera on | Camera listed as nearby, model recognised from its name |
| B2 | PAIRING REGISTRATION on the camera → *Pair* | Same code on iPhone and camera; after confirming, *Connected over Bluetooth*; firmware shown |
| B3 | Leave connected | Camera clock matches the phone; log shows "Camera asked for the time" |
| B4 | Turn on *Share location for geotags*; take a photo | Photo EXIF has GPS; log shows "Camera asked for location" |
| B5 | *Take Photo* | Shutter fires once |
| B6 | Turn the camera off and on | FilmLab reconnects without pairing again |
| B7 | Pair XApp on the same phone, then reopen FilmLab | Record what happens (SELECT PAIRING DESTINATION) |

### Wi‑Fi checks (after B1–B6)

| ID | Check | Expect |
|---|---|---|
| W1 | Camera: PLAYBACK › WIRELESS COMMUNICATION; iPhone on its network; *Import Photos* › *Connect* | "Press OK on the camera"; after OK, the card's photos, newest first |
| W2 | Scroll the grid quickly | Thumbnails fill what's on screen first; no hang (ObjectInfo before GetThumb) |
| W3 | *Import New Photos* on ~20 JPEGs | Files in Photos at full size (compare pixel size with the card); MB/s shown; log has no errors |
| W4 | Run W3 again | Nothing re-downloaded ("imported" badges) |
| W5 | Bluetooth connected; *Connect to <camera>* | Camera starts Wi‑Fi by itself; iPhone joins (or asks to join in Settings without the capability) |
| W6 | After W5, import one JPEG | Full-size original (record its size: confirms what `D226 = 2` means) |
| W7 | Turn the camera off mid-import | "Connection dropped" message; finished photos are in Photos |
| W8 | Stopwatch: XApp vs FilmLab, camera on → 20 JPEGs in Photos | Record both times here |
