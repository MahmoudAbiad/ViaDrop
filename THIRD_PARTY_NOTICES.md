# Third-party notices
ViaDrop is proprietary. Third-party licenses retain their full effect.
OneSend: only unmodified fountain.dart and protocol.dart, MIT.
ggwave: unmodified core, MIT; Reed-Solomon MIT; Ooura FFT permissive commercial license.
Cairo and Manrope fonts: SIL OFL 1.1, official google/fonts sources.
Complete copied notices are in assets/licenses. Dart package notices are collected
from the exact resolved package tree. See LICENSE_AUDIT.md for release limitations.

## Cyrinx portable OFDM subset and KISS FFT

Cyrinx Copyright 2026 Primatech Paper Co LLC. The unmodified portable bulk PHY
and FFT adapter subset comes from dweekly/cyrinx revision
695655221ab9b9f01f2c7698ea7280b5e8aa3804 under Apache-2.0.
See assets/licenses/Cyrinx-Apache-2.0.txt and Cyrinx-NOTICE.txt.
KISS FFT Copyright (c) 2003-2010 Mark Borgerding, BSD-3-Clause; complete
license and attribution are in assets/licenses/KISS-FFT-BSD.txt.
Source checksums and exact copied files: docs/CYRINX_SOURCE.json.
No Swift/Kotlin application, Python reference modem or external crypto is copied.
ViaDrop's JNI/streaming wrapper is original application code.


## Experimental color transport (0.3.0)

The separate ViaDrop color codec component and pinned libcimbar
156fbb9c675ca9641f6559922b7025a0f2ee8125 are MPL-2.0 covered source.
The exact source and original notices are distributed alongside the test APK
as the ViaDrop-color-covered-source Actions artifact. Source and build tools:
https://github.com/MahmoudAbiad/ViaDrop/tree/main/components/color_codec and
https://github.com/MahmoudAbiad/ViaDrop/tree/main/tools/cimbar . This does not
relicense the independently written proprietary ViaDrop application.

The build downloads the official OpenCV 4.10.0 Android SDK at a recorded SHA-256.
OpenCV is Apache-2.0; its selected static components have their own dependencies.
All SDK-delivered license directories and LICENSE/COPYING/NOTICE files are
preserved in the APK's viadrop-color-notices assets and Flutter license page.
The build-generated SOURCE_MANIFEST.json inventories those exact notice hashes.
Pinned libcimbar dependency licenses are preserved from the checked source
manifest; zstd uses its BSD option, not its alternative GPL option. See
LICENSE_AUDIT.md for remaining commercial release review.
