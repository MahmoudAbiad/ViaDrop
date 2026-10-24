# Architecture

- `lib/core/transfer.dart`: shared transport contracts, capabilities and state model.
- `lib/core/manager.dart`: encrypted staging, verification, local history and storage.
- `lib/core/vault.dart`: streaming VDP1 authenticated AES-256-GCM records with final
  length/SHA-256 checks. PBKDF2 converts the supplied passphrase into a file key.
- `lib/core/qr_pairing.dart`: ephemeral X25519 and transcript-bound secret derivation;
  shared by QR and acoustic pairing. Rejects all-zero shared secrets (RFC 7748 §6.1).
  A domain-separated SHA-256 fingerprint (48 displayed bits) lets users compare
  the exchange in person. It is not a password and is not sent as a secret.
- `lib/core/acoustic_pairing.dart`: HMAC ready acknowledgement; this proves key
  possession, not the identity of an intended human. The UI also requires comparison.
- `lib/engines/physical.dart`: bounded in-memory small-file fountain packets,
  CRC validation and session-bound reconstruction. Screens call QR/camera or
  speaker/microphone adapters only. These paths have no LAN/Bluetooth fallback.
- `lib/engines/lan.dart`: custom LAN protocol, not LocalSend wire compatibility.
- `lib/engines/native.dart` and Kotlin MainActivity: Android Bluetooth and audio I/O.
- `lib/screens`: physical-channel UX; `radio_transfer_page.dart`: LAN/Bluetooth UX.

Pairing and envelope security have not undergone independent security review.
Fingerprint comparison requires checking both physical screens. Do not describe
this experimental application as independently audited end-to-end encryption.
Reference: https://www.rfc-editor.org/rfc/rfc7748#section-6.1
