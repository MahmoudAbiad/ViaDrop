# Architecture

- `lib/core/transfer.dart`: shared transport contracts, capabilities and state model.
- `lib/core/manager.dart`: encrypted staging, verification, local history and storage.
- `lib/core/vault.dart`: streaming VDP1 authenticated AES-256-GCM records with final
  length/SHA-256 checks. PBKDF2 converts the supplied passphrase into a file key.
- `lib/core/one_way_session.dart`: creates a 32-byte random secret and a
  session identifier. Encodes both in a short VDS3 profile-aware announcement, parsed
  identically from a static start QR and an audible ggwave start packet.
  The sender keeps the secret to seal the payload; receiver reads it from
  the announcement and filters fountain packets by session ID.
- `lib/core/qr_pairing.dart` and `lib/core/acoustic_pairing.dart`:
  previous two-way X25519 protocol remains in the repository for legacy tests
  only; current QR/audio UI does not invoke it.
- `lib/core/physical_profiles.dart`: registered implemented/planned profile
  definitions, hardware-based candidate eligibility, and mode mapping.
- `lib/widgets/physical_profile_selector.dart`: shared Flutter dropdown,
  disabled unsupported/unimplemented profiles, capability refresh.
- Kotlin `MainActivity.probePhysicalCapabilities`: Camera2 target FPS,
  display refresh, audio 48 kHz buffer support, native OFDM initialization and
  near-ultrasound hardware flags (candidate checks, not two-phone validation).
- `lib/engines/physical.dart`: bounded in-memory small-file fountain packets,
  CRC validation and session-bound reconstruction. Screens call QR/camera or
  speaker/microphone adapters only. These paths have no LAN/Bluetooth fallback.
- `lib/engines/lan.dart`: custom LAN protocol, not LocalSend wire compatibility.
- `lib/engines/native.dart` and Kotlin MainActivity: Android Bluetooth and audio I/O.
- `lib/screens`: physical-channel UX; `radio_transfer_page.dart`: LAN/Bluetooth UX.

Security trade-off: VDS2 physically broadcasts the symmetric encryption secret.
The AES-GCM records verify integrity against accidental corruption and against
someone who *did not receive* the secret, but an observer of the announcement
can decrypt and forge frames. There is no peer authentication, no forward secrecy,
and no receiver acknowledgement. Do not call this end-to-end confidential
encryption. The older X25519 pairing code is not used in current physical flows.

Fast audio uses an isolated `ofdm_codec` JNI adapter over a pinned portable Cyrinx
subset and KISS FFT. Ggwave handles the short profile-aware one-way start announcements
and slower optional data transfer; receiver playback is never started.
The receiver runs bounded OFDM work on a separate worker so it does not block
AudioRecord. All files still pass through the same encrypted fountain transport
and final SHA-256 verification. Users select fast/slow audio explicitly; no
network transport is called in either path.


## Native color optical path

The proprietary Flutter controller injects ColorOptical.present into the same
PhysicalEngine packet producer. ColorBridge owns textures and the isolated
MPL-2.0 ColorFrameRenderer/ColorCameraSession via narrow Java APIs. The native
codec never receives a path or file-saving responsibility. The receiving camera
hands raw packet bytes through a separate event channel, tagged with its native
generation, to PhysicalDecoder; the manager still verifies before saving.
There is no socket or radio operation in this color data path.

Camera and display resources release asynchronously; Flutter awaits cleanup
before opening another native session. A camera start first relinquishes the
MobileScanner instance used for the invitation. Backgrounding cancels the
color session. Application restart/resume of a partial transfer is not claimed.
