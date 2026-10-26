"""Apply color inputs after flutter create; avoid environment-specific repo paths."""
import os
from pathlib import Path

deps = Path(os.environ['VIADROP_COLOR_DEPS']).resolve()
p = Path('android/app/build.gradle.kts')
s = p.read_text()
# Native code and libc++ must use the same pinned NDK on both APK variants.
if 'ndkVersion = flutter.ndkVersion' not in s:
    raise SystemExit('Inspect generated NDK declaration')
s = s.replace('ndkVersion = flutter.ndkVersion', 'ndkVersion = "28.2.13676358"')
config = '''
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DCIMBAR_SOURCE=DEPS/libcimbar",
                    "-DOpenCV_DIR=DEPS/OpenCV-android-sdk/sdk/native/jni",
                    "-DOpenCV_STATIC=ON"
                )
                targets += listOf("viadrop_audio", "viadrop_color_jni")
            }
        }
'''.replace('DEPS', str(deps))
s = s.replace('defaultConfig {', 'defaultConfig {'+config, 1)
s = s.replace('release {', 'release {\n            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")', 1)
p.write_text(s)
