# ViaDrop 0.4.0 — experimental LAN and Bluetooth

## Implemented

- Home exposes two real transports alongside optical and acoustic modes.
- Wi-Fi LAN: private IPv4 UDP announcements, manual private IP fallback, HTTP
  consent/ticket exchange and streamed VDP1 ciphertext. A router or manually
  configured hotspot is needed, not an Internet connection. Not LocalSend wire
  compatible. No automatic switching to Bluetooth or any Internet service.
- Avoid per-chunk flush stalls: Dart IOSink/HTTP addStream applies backpressure;
  progress notifications are throttled to 100 ms. File data is not held whole
  in RAM. Encrypted size limit is 1 GiB plus envelope allowance.
- Receiver explicitly accepts each transfer. Sender success waits for receiver
  decryption, authenticated reconstruction and SHA-256 validation.
- Both radio modes use a user-agreed 12+ character shared passphrase. The
  passphrase/key is never transmitted. UDP/HTTP offer metadata is not private;
  application ciphertext is authenticated by the existing Vault. This is not
  a completed independent security audit or authenticated discovery protocol.
- Secure Android Classic RFCOMM, bonded peers only, separate native channel and
  worker from audio. 64 KiB buffers, single transfer/session owner, 100 ms
  progress updates. No insecure socket, reflection or BLE/network fallback.
- Android 12+ CONNECT/SCAN runtime permissions; Android 6 does not request
  unrelated location permission to list already-bonded devices. Pairing and
  device discovery use Android Bluetooth settings, not in-app scan yet.
- Bluetooth connect/header/data/consent/verification deadlines; socket close
  unblocks pending I/O. Stop replies after the owning worker's finally cleanup.
  Old-client stop and stale decision IDs cannot affect a new owner/request.
- Radio route cancels active work on background/exit, provides cancel, local
  IPs, estimated speed/time, and opens a verified received file.
- Route staging folders are separate: initializing one manager no longer
  deletes another operation's temporary or partially reconstructed files.

## Technology choice (official documentation reviewed 2026-10-26)

- https://developer.android.com/develop/connectivity/overview
- https://developer.android.com/develop/connectivity/bluetooth/connect-bluetooth-devices
- https://developer.android.com/develop/connectivity/wifi/wifi-aware
- https://developer.android.com/develop/connectivity/wifi/wifip2p

Wi-Fi Aware is a future capability for supporting Android 8+ hardware. It
cannot serve Android 6 J7. Wi-Fi Direct is a separate planned adapter, not a
label for ordinary LAN. BLE L2CAP/other modern capabilities need a separately
validated device matrix; no claim that a new Bluetooth version changes the
radios physically present in these phones. Nearby Connections mixes radios,
so it is not used as a silent implementation of either manually chosen channel.
No new third-party dependency was imported for this change.

## Validation

Automated test/build results will be recorded after CI completes. New tests
exercise real host LAN encrypted roundtrip, refusal, wrong passphrase, empty
Arabic-named file, cancellation during consent, forbidden public IP, and Dart
Bluetooth permission/client/decision/cancellation boundaries. These are NOT
physical Wi-Fi or Bluetooth tests. Native RFCOMM socket behavior, pairing,
performance, timeout behavior and resource release require two actual phones.

## Device acceptance (not executed)

Use 0.4.0 on BOTH devices. First preserve the separate 0.3.2 camera/audio
results. For Wi-Fi connect both devices to the same router or one phone's
hotspot with mobile data off. Set the same strong passphrase, enable receive,
select discovered receiver (or its shown private IP), send text/empty file/
photo/PDF/random binary, accept and compare restored bytes/SHA-256. Reverse
phones, refuse a transfer, enter a wrong passphrase, cancel mid-file, remove
Wi-Fi then reconnect. Repeat 10 MiB and larger only after small files pass.
Router client isolation may block discovery and transfers.

For Bluetooth pair in Android settings, disable Wi-Fi/mobile data, set the
same passphrase, refresh bonded peers, enable receive on the other device,
then send/accept/verify the same cases. Test disabled radio, denied permission,
background, out-of-range, late consent and cancel/retry. Start small; RFCOMM is
not expected to match Wi-Fi file throughput. Record phone/build, file size,
duration, pass/failure and error text. Do not report host simulation as a phone
result.

## Remaining gates

- Physical A24/J7 acceptance, instrumentation/heap/power measurements and
  security review. No measured throughput claim.
- Resume, multiple-file batch UX, in-app Bluetooth discovery, Wi-Fi Direct and
  Wi-Fi Aware are not implemented or advertised as available.
- No foreground service: transfers stop on background instead of claiming
  guaranteed background operation. LAN discovery may need device/router tuning.
- Receiver verification deadline is 180 seconds on Bluetooth; very large files
  on slow devices may exceed it and require measured tuning.
- History persistence across overlapping route instances and periodic stale
  staging cleanup need separate work; no global destructive cleanup on open.
