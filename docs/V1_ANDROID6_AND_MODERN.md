# ViaDrop V1: Android 6 and modern releases

There are two independent GitHub Actions workflows on `main`:

- **Android 6 / Galaxy J7 Legacy**: Flutter 3.32.8, minSdk 23, armeabi-v7a, `ViaDrop-V1-Android6-J7-ARM32-release.apk`. A separate dependency manifest `ci/pubspec_android6.yaml` keeps the older framework/plugin compatibility without downgrading the modern app.
- **Modern Android**: Flutter 3.47.8, minSdk 24, arm64-v8a, `ViaDrop-V1-Modern-ARM64-release.apk`.

Both build optimized `--release` APKs and independently run the Dart tests, analyzer, and APK badging/native-library checks.

Neither APK is a fully signed Play Store production build; each currently uses an internal testing identity. Versions may need to be uninstalled before switching identity, after backing up received files.

Android 6 is end-of-life, so this build should be used for local trials and not considered security-supported. Both camera QR and acoustic transfer still require physical two-device verification.

The modern ARM64-only build is for 64-bit Android devices. Older Android 7+ devices running only 32-bit ARM should use a separate ARM32 build, not the ARM64 artifact.
