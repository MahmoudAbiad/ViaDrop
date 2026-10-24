# Validation

## Automated simulation

- `recovery_test.dart`: state transitions, unsafe names, AES-GCM round trip,
  incorrect password, modified ciphertext and cleanup.
- `physical_roundtrip_test.dart`: loss/duplicates, batch QR capture, corrupt payload,
  encrypted envelope through fountain packets, session binding, Base45, and
  legacy X25519 crypto tests.
- `one_way_session_test.dart`: one-way invitation parsing, independent keys,
  malformed starts, session filtering and encrypted fountain reconstruction.
- `physical_profiles_test.dart`: implemented/disabled profile checks, probe
  failures, automatic local recommendation, and VDS3 mode agreement.
- `physical_profile_selector_test.dart`: disabled dropdown entries.
- `qr_profile_capacity_test.dart`: QR v13/v17 encoded fountain frames fit.
- `physical_receive_metrics_test.dart`: goodput and frame counters.
- Actual RX payload goodput and accepted/rejected frame counts are displayed
  after a verified transfer. They do not include initial pairing or decryption
  time, and do not reveal missing over-the-air frames.
- Physical device probe and transport settings require on-device tests; CI
  simulation does not establish real cross-device codec performance.
- `lan_integration_test.dart`: local host HTTP consent/streaming/error scenarios.
- `native/audio_loopback.cpp`: actual ggwave PCM encode/decode at 48 kHz signed
  16-bit mono, audible-fast and ultrasound-fast, 64/132/140-byte packets, with
  silence and deterministic low-amplitude additive noise. The 132-byte case
  covers the current 100-byte fountain payload plus 32-byte header.

These are simulations. They do not test a real camera, Android microphone,
acoustic echo, device permissions, Bluetooth radios or speaker frequency response.
The baseline c3de76f had successful legacy/modern CI runs; each new commit needs
its own test/build results in GitHub Actions.

## Required two-device tests — NOT EXECUTED here

Use Samsung J7/Android 6 ARM32 and a modern ARM64 phone. Record both model/OS,
commit, APK hash, channel, mode, input/output SHA-256, elapsed time and outcome.

1. QR: airplane mode, radios off. Show a static one-way start QR on sender;
   scan it once with the receiver. Wait before pressing Start, then verify the
   sender's 3-second countdown and automatic switch to fountain QRs. Test
   empty files, Arabic text/names, image, PDF, random bytes, missing frames,
   stop/restart and fast mode. No response scan or confirmation is expected.
   Never accept partial output.
2. Audio: airplane mode, radios off. Start receiver first: it must listen
   silently with **no playback**. Sender then emits start announcement(s) and
   file data. Verify no receiver sound during any phase. Begin with short text,
   then binaries and larger files. Test both slow/fast data paths and volume/
   noise/placement conditions. Old and new APKs are not interoperable.
   - Block first ggwave announcement, then restore audio proximity. Confirm
     another announcement is sent after 24 data frames and receiver can join.
   - Stop/restart while sending start tones, during OFDM data, during decoding,
     or while finalizing. Check no orphan microphone or stale playback.
   - Confirm a second unrelated session's data cannot contaminate an active
     receiver session, and AES-GCM and SHA-256 verify the final file.
   - Receiver sends no ACK; sender must be stopped manually after verifying
     success on the receiver.
3. Protocol/security: malformed VDS3 QR/audio announcements are rejected.
   An observer who captured VDS3 can decrypt this intentionally public-key
   announcement; explicitly warn users not to send sensitive files. Legacy
   X25519 unit tests are retained but no longer drive either physical UI.
4. LAN: offline router, accept/reject, multiple files, large-file memory use,
   interrupted connection, bad digest, filename traversal and output cleanup.
5. Bluetooth: secure paired RFCOMM, permission denial, rejection, interruption,
   repeated sessions, correct progress and output hashes.
6. All: background/foreground, navigation away, screen lock, cancellation during
   preparation/verification, temp cleanup, empty files and insufficient storage.

No physical completion rate or measured on-device throughput is available yet.

## Physical profile compatibility (new)

See [docs/PHYSICAL_PROFILES.md](docs/PHYSICAL_PROFILES.md). Test each transfer
with the same exact profile on both phones, then deliberately choose a mismatch:
QR should refuse the start while retaining its scan screen, and acoustic should
stop listening and show the sender's profile. Newly built VDS3 APKs cannot
interoperate with old VDS2 builds. Planned modes remain disabled even on
top-end phones. Probe results are only preliminary hardware evidence.

## Fast-audio implementation checkpoint

`bash tools/test_ofdm.sh` builds the exact vendored C codec and original C++
streaming adapter. Local simulation passed: nine OFDM configurations/noise/echo
cases and two four-packet unaligned PCM16 streams (clean and noise plus a 5 ms
20% echo). Every decoded packet matched the original bytes; the receiver requires
all CRC blocks to pass before releasing a packet. It buffers at most 65,536
samples and Android queues at most 48 PCM reads, discarding a backlog on overload.

The selected profile is 16-QAM rate 1/2, 1.1–16 kHz, 48 kHz mono: 1,024 modem
bytes per 0.6613-second waveform, carrying a 900-byte fountain block plus framing.
The 180 ms gap and fountain overhead reduce useful throughput. A 48 KiB input
is estimated around 1–2 minutes plus start announcements under favorable conditions;
this is NOT a device benchmark or upper bound. Slower mode remains explicit.
Both phones must select the same mode. Fast mode is audible only.

Physical tests must now additionally exercise Android CPU load/backlog behavior,
room echo, frequency response, microphone gain and sample-clock drift. These
were not modeled comprehensively by the deterministic simulation.
