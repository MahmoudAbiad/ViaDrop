# Physical transfer profiles (QR & acoustic) — main

## Overview

Each screen displays a shared Arabic dropdown, fastest candidate first. The
selection controls the **actual existing codec**, not merely a cosmetic label.
Unimplemented faster options appear disabled. Enabled means "local hardware
checks passed", NOT that two-phone reception is proven.

The device probe is exposed by `MainActivity.kt` as
`MethodChannel('app.viadrop/native').physicalCapabilities`:
- QR: a camera feature flag, Camera2 back-camera target FPS ranges, and
  current display refresh rate. Fast QR requires >=30 FPS available and
  >=50 Hz screen; dense QR requires >=30 FPS and ~60 Hz. Standard QR only
  requires a camera. Dense mode uses the larger version 17 matrix, without
  any claim that the camera can reliably decode nine dense codes per second.
- Audio: microphone presence, AudioRecord/AudioTrack minimum buffer for
  PCM16 mono 48 kHz, and successful native OFDM init. High frequency
  additionally requires Android AudioManager near-ultrasound property flags.
  Experimental Turbo reuses 16-QAM OFDM but reduces inter-frame silence from
  180 ms to 40 ms; local candidacy requires Android 8+ and >=4 CPU cores.
  The actual improvement and decoding error rate are still unmeasured.
- If the probe fails, no mode is enabled (fail closed), with a retry button.
- The probe does **not** measure speaker response, camera autofocus,
  sustained decoder throughput, environmental echo or a remote phone.

## Implemented profiles

| Profile ID | Role | Native implementation | Selection |
| --- | --- | --- | --- |
| `qr-ultra` | camera | Fountain+QR v40, 2400-byte blocks, up to 30 FPS | Android >=8, >=4 cores, 900px screen, camera >=30 FPS and display ~60 Hz |
| `qr-color` | camera | Native CIMBAR mode 4, 2400-byte fountain blocks, 100ms minimum gap plus actual encode time | Codec present, Android >=6, >=4 cores, camera >=15 FPS; sender additionally needs 1080px display; camera output checked at start |
| `qr-grid` | camera | Four independent QR v17 tiles, 512 bytes/tile, 10 screen updates/s | Same preliminary hardware gate as Ultra |
| `qr-dense` | camera | Fountain+QR v17, 512-byte blocks, 9 FPS (experimental) | Camera >=30 FPS and display ~60 Hz |
| `qr-fast` | camera | Fountain+QR v13, 320-byte blocks, 7 FPS | Camera >=30 FPS and display >=50 Hz |
| `qr-standard` | camera | Fountain+QR v13, 280-byte blocks, 5 FPS | Camera present |
| `audio-turbo` | audio | Existing 900-byte OFDM modem with 40 ms frame gap (experimental) | Android >=8, >=4 cores, native OFDM and PCM 48 kHz |
| `audio-ofdm` | audio | Cyrinx OFDM 900-byte blocks | PCM 48 kHz input/output and native OFDM init |
| `audio-audible` | audio | GGWave audible 100-byte blocks | PCM 48 kHz input/output |
| `audio-ultrasound` | audio | GGWave high-frequency 100-byte blocks | PCM 48 kHz + near-ultrasound hardware properties |

Order is by expected throughput candidate, not independently measured
performance. GGWave high frequency does *not* imply higher throughput
than audible mode; both use 100-byte blocks.

## Match the modes

1. The sender and receiver independently pick the **same exact profile ID**.
2. The new one-way start protocol is `VDS3:<session-id>:<random-secret>:<profile-id>`.
3. The receiver rejects a mismatched profile and shows the sender's mode name.
   It never silently falls back to another transport or tries to decode an
   unknown payload.
4. QR maintains a static start QR and the sender's manual three-second count.
   Acoustic maintains its audible start message and receiver-only microphone
   operation, without an acknowledgement sound.
5. VDS3 is not compatible with older VDS2 APKs. Install the same app revision
   on both devices.
6. Both sides may recommend different modes due to hardware; local auto-choice
   does not imply the remote device supports that mode.

### Security

A start announcement contains the symmetric file secret in plaintext.
Anyone who copies the start QR or decodes the audible start can decrypt the
file transmission. SHA-256 and the AES-GCM envelope verify received bytes
but provide no confidentiality from someone who captured the announcement.
Do not send sensitive documents through these one-way physical modes.

### What remains

- Real hardware soak/roundtrip tests, J7 Android 6 and modern Android phone
- Received goodput and valid/rejected frame counts now appear after a completed
  transfer; missing airborne frames cannot be counted without an agreed
  sequence model. Record these metrics on both Android 6 and modern phones.
- User-permitted persistence of a previously validated (rather than merely
  detected) mode
- On-device tuning of the implemented native color decoder and QR densities; new OFDM modulation; real negotiation
  (which is impossible without a reverse channel)

## Manual smoke checks

- Disable camera permission, then scan: should request permission and fail
  gracefully; probe flags alone do not guarantee permission is granted.
- Open dropdown on Android 6 J7 and A24: planned modes disabled. Each real
  mode must show an evidence-based status, not claim it was tested.
- Choose QR Standard on both, transfer a short text file; repeat in QR Fast.
- Choose different QR modes: receiver must show the sender's mode, reject
  that start, and allow matching the dropdown before scanning again.
- Choose GGWave Audible on both and send a short note with receiver silent;
  repeat for OFDM if candidate supported.
- Choose different audio modes: receiver must stop with a clear mismatch
  message. Do not broadcast any ACK.
- Retry the capability probe after a denied permission/error.
- Test cancellation, return to screen, and wrong versions of the APK.


## Color camera handoff

For `qr-color`, MobileScanner scans only the opening QR. The active scanner is
stopped and removed before Camera2 starts, avoiding simultaneous camera owners.
Camera2 acquires YUV pixels and passes native decoded packet bytes directly to
the fountain decoder; it does not convert colored frames into QR strings.
The native generation appears in every event and is checked by Flutter before
accepting data. A new transfer always uses a new one-way session ID.

The receiver explicitly chooses a limited-range BT.601 or BT.709 calibration;
there is no assertion that every camera uses the default. A phone with a 720px
screen may receive from a 1080px sender if its camera output configuration works.
Physical J7/A24 compatibility and usable goodput are still unverified.
