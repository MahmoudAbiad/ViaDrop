# SPDX-License-Identifier: MPL-2.0
# Copyright 2026 Mahmoud Abiad
"""Prepare original adapter sources and preserve every supplied SDK notice.
No license is changed; the application's source is excluded from source bundle.
"""
import hashlib
import json
import shutil
import sys
import tarfile
from pathlib import Path

root, deps = map(Path, sys.argv[1:])
source = deps / 'libcimbar'
sdk = deps / 'OpenCV-android-sdk'
manifest = json.loads((root/'tools/cimbar/source.json').read_text())
for name, expected in manifest['license_files'].items():
    if hashlib.sha256((source/name).read_bytes()).hexdigest() != expected:
        raise SystemExit('Source/license snapshot mismatch: '+name)

# Compile only production files, never the host-JVM test programs.
dest = root/'android/app/src/main/java/app/viadrop/color'
dest.mkdir(parents=True, exist_ok=True)
for name in ['ColorCodec.java', 'Yuv420Rgb.java']:
    shutil.copy2(root/'components/color_codec/java/app/viadrop/color'/name, dest/name)
for path in (root/'components/color_codec/android/app/viadrop/color').glob('*.java'):
    shutil.copy2(path, dest/path.name)

notices = root/'assets/licenses/color'
notices.mkdir(parents=True, exist_ok=True)
# Preserve all notice files delivered by the official SDK, including filenames
# such as zlib.txt which don't themselves contain the word 'license'.
license_dirs = [p for p in sdk.rglob('*') if p.is_dir() and p.name.lower() in ('licenses', 'license')]
notice_files = {p for p in sdk.rglob('*') if p.is_file() and p.name.lower().startswith(('license', 'copying', 'notice'))}
for directory in license_dirs:
    notice_files.update(p for p in directory.rglob('*') if p.is_file())
if not notice_files:
    raise SystemExit('Official OpenCV SDK has no notices; do not distribute')
for path in sorted(notice_files):
    relative = path.relative_to(sdk)
    target = notices/'opencv'/relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, target)
for name in manifest['license_files']:
    path = source/name
    target = notices/'libcimbar'/name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, target)
shutil.copy2(root/'components/color_codec/LICENSE', notices/'ViaDrop-color-MPL-2.0.txt')
record = {
    'libcimbar_revision': manifest.get('revision', '156fbb9c675ca9641f6559922b7025a0f2ee8125'),
    'opencv_version': '4.10.0',
    'opencv_sdk_sha256': '464d55abe64b53af3aeb73197cf4620535abd909916d06e6a8b7c32712013966',
    'opencv_notices': {str(p.relative_to(sdk)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(notice_files)},
    'selected_opencv_targets': ['core', 'imgproc', 'calib3d', 'imgcodecs', 'photo'],
    'distribution': 'experimental internal APK; full product audit remains a release gate',
}
(notices/'SOURCE_MANIFEST.json').write_text(json.dumps(record, indent=2)+'\n')
print('OpenCV notice inventory:', '\n'.join(record['opencv_notices']))
# Complete, exact covered component + pinned upstream source, not a source offer
# relying on a branch staying unchanged. Bundle follows the APK in Actions.
dist = root/'dist'
dist.mkdir(exist_ok=True)
with tarfile.open(dist/'ViaDrop-color-covered-source.tar.gz', 'w:gz') as archive:
    def include(info):
        return None if '/.git' in info.name else info
    archive.add(source, arcname='libcimbar', filter=include)
    archive.add(root/'components/color_codec', arcname='viadrop-color-codec')
    archive.add(notices, arcname='notices')
    archive.add(root/'tools/cimbar', arcname='build-tools')
    archive.add(root/'components/color_codec/LICENSE', arcname='build-tools/LICENSE')
# Include notices in Android's asset tree as well as Flutter's license assets.
android_assets = root/'android/app/src/main/assets/viadrop-color-notices'
if android_assets.exists():
    shutil.rmtree(android_assets)
shutil.copytree(notices, android_assets)
print('PASS pinned source/license hashes, SDK notice retention and covered-source bundle')

paths = sorted(str(p.relative_to(root)) for p in notices.rglob('*') if p.is_file())
(notices/'INDEX.json').write_text(json.dumps(paths, indent=2)+'\n')
pubspec = root/'pubspec.yaml'
text = pubspec.read_text()
asset_dirs = sorted({str(p.parent.relative_to(root))+'/' for p in notices.rglob('*') if p.is_file()})
text = text.replace('  fonts:', ''.join('    - '+p+'\n' for p in asset_dirs)+'  fonts:', 1)
pubspec.write_text(text)
