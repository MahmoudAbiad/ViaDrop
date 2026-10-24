# ViaDrop V1 — ARM32 trial APK

This preview is for QR camera transfer and acoustic audio transfer only.
Wi-Fi and Bluetooth development is deferred.

## Build target

- Flutter optimized **Release** APK (not the large Debug build)
- ABI: **armeabi-v7a / ARM32**; the Android build verifies `libflutter.so` and `libviadrop_audio.so`
- Minimum OS for the current Flutter engine: **Android 7.0 (API 24)**
- GitHub Actions output: `ViaDrop-V1-J7-ARM32-release.apk`
- Release mode does **not** imply production distribution signing. The generated Flutter template uses a development signing identity until an owner-supplied secure release key is configured.

## Galaxy J7 compatibility

The name "Galaxy J7" covers several devices and Android versions.
J7 devices running Android 7.0+ with 32-bit ARM runtime are the intended test targets.
**Android 6.0 / 5.1 J7 models are not supported by this Flutter V1 build.**
Do not lower the Gradle minSdk alone: that would not restore runtime support in Flutter 3.47.

Compatibility requires checking the exact model and the **installed Android version**, and a real two-device camera/audio transfer test.

## Install/testing

Download the successful GitHub Actions artifact, extract the APK, and install it on Android 7+.
Use the same passphrase (at least 12 characters) on two devices.
Test QR with a tiny file first; test audio with a short text note.
Do not claim end-to-end physical device validation until actually observed.
