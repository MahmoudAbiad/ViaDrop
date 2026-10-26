# License audit — incomplete, release gate

ViaDrop code is proprietary; public visibility is not an open-source license.
Existing notices are in THIRD_PARTY_NOTICES.md and assets/licenses.

| Component | Source/version recorded | Current evidence |
| --- | --- | --- |
| OneSend fountain/protocol | makerjackie/onesend, 39e95ce59df2f2dc38d2556dd4239cec6a0ca35f | MIT subset and notices retained; no cimbar/WASM copied |
| ggwave | ggerganov/ggwave, 060aec73dd7123ccac200442f75bdc7369795ffe | MIT notice retained |
| Reed-Solomon in ggwave | vendored source | MIT notice retained |
| Ooura FFT in ggwave | vendored source | upstream permission notice retained |
| Cairo / Manrope | Google Fonts | OFL notices bundled |
| Flutter/Dart and plugins | two pubspec profiles | full resolved/transitive and native audit still required |

The fast-audio experiment adds only the reviewed Cyrinx portable bulk/FFT subset
(Apache-2.0) and its KISS FFT dependency (BSD-3-Clause). Their source files are
unchanged, with SHA-256 inventory in docs/CYRINX_SOURCE.json and full license/NOTICE
assets bundled. KISS FFT BSD text was retrieved from its recorded upstream commit
5e5058275a72dfc9e474bf78c8daea0ff29c7eb2, LICENSES/BSD-3-Clause.
No whole Cyrinx application, Swift dependencies or Python runtime is shipped. Do not treat
this file as complete distribution clearance. Before release record exact resolved
versions/hashes for both profiles, Android Maven/native artifacts, licenses and
required notices; replace any incompatible or unlicensed component. Linux-only
transitive packages must be assessed separately before adding desktop targets.


## Experimental color distribution — 0.3.0

- Separate color component: MPL-2.0, full source/build tools retained. Pinned
  libcimbar source/license hashes are checked before building. The exact source
  archive is uploaded alongside each test APK, without the independent
  proprietary application source.
- Selected OpenCV native targets: core, imgproc, calib3d, imgcodecs, photo and
  their static dependencies. Official Android SDK 4.10.0 archive SHA-256 is
  verified. Every SDK-supplied license directory and top-level notice is retained
  (including notices for optional unused components; retaining a notice does
  not establish that its component is linked). Choose the BSD option for
  dual-licensed ittnotify; no GPL option is selected. zstd also uses BSD.
- Pinned NDK 28.2.13676358 notices are retained for the packaged C++ runtime and
  compiler support. Generated SOURCE_MANIFEST.json includes notice hashes and
  exact application/source revision. A full transitive Flutter/Maven audit and
  reachability review remain required before commercial release.
- APK distribution must retain source access for the covered component if this
  repository becomes private again. Do not treat a temporary Actions URL as a
  permanent source-distribution plan for a store release.

The test APK is not a declaration that legal, security or device acceptance
criteria for a production product have all passed. No Decimen AGPL code is used.
