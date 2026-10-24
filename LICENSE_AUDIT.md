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
