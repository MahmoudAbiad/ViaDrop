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
  >=50 Hz screen; standard QR only needs a camera.
- Audio: microphone presence, AudioRecord/AudioTrack minimum buffer for
  PCM16 mono 48 kHz, and successful native OFDM init. High frequency
  additionally requires Android AudioManager near-ultrasound property flags.
- If the probe fails, no mode is enabled (fail closed), with a retry button.
- The probe does **not** measure speaker response, camera autofocus,
  sustained decoder throughput, environmental echo or a remote phone.

## Implemented profiles

| Profile ID | Role | Native implementation | Selection |
| --- | --- | --- | --- |
| `qr-ultra` | camera | Not built | Always disabled |
| `qr-dense` | camera | Not built | Always disabled |
| `qr-fast` | camera | Fountain+QR v13, 320-byte blocks, 7 FPS | Camera >=30 FPS and display >=50 Hz |
| `qr-standard` | camera | Fountain+QR v13, 280-byte blocks, 5 FPS | Camera present |
| `audio-turbo` | audio | Not built | Always disabled |
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
- Measured goodput and loss tracking per codec/device pair
- User-permitted persistence of a previously validated (rather than merely
  detected) mode
- Fast camera scanner and high-density QR, new OFDM profiles, real negotiation
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
