# Development

Work on `main`. `recovery-dev` is an unchanged historical development branch.
Do not force-push or replace history. Check remote head before each update.

The CI workflows currently regenerate the missing Android scaffold, add native
CMake audio wiring and permissions, then resolve dependencies and build APKs.
Modern Flutter is pinned to 3.47.8; Android 6 uses 3.32.8 and
`ci/pubspec_android6.yaml`. Use Java 17 for the legacy build.

Dart validation after preparing the selected profile:
```
flutter pub get
flutter test
flutter analyze --no-fatal-infos
```

Native simulation, without Flutter or Android:
```
g++ -std=c++17 -O2 -Iandroid/app/src/main/cpp/include test/native/audio_loopback.cpp android/app/src/main/cpp/ggwave-src/ggwave.cpp -o /tmp/viadrop-audio-test
/tmp/viadrop-audio-test
```

Never commit signing keys, credentials or personal test files. CI release-mode
artifacts currently use generated test signing and are not Play Store releases.
Before production: commit reviewed Android scaffold/resources, lock both dependency
profiles, audit resolved licenses, configure protected signing and device test gates.


## Building the color APK inputs

The APK workflows install NDK 28.2.13676358, export VIADROP_COLOR_DEPS to an
absolute build-only dependency directory, then run tools/cimbar/prepare-app.sh
and tools/cimbar/configure-gradle.py after recreating the Android scaffold.
The preparation verifies the pinned upstream revision/license hashes and
OpenCV SDK archive checksum, copies only production Java adapters, registers
all supplied license assets, and produces the exact covered-source archive.
Do not commit the generated dependency tree, copied Java or APK staging files.
The app's native build targets are explicitly viadrop_audio and
viadrop_color_jni. Both use the pinned NDK's shared C++ runtime. Release JNI
names are kept by proguard-rules.pro. APK verification checks signature, minSdk,
ABI, native library presence and notice-manifest presence before artifact upload.
Production signing remains out of scope; these APKs use internal test signing.
