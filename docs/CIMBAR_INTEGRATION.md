# CIMBAR integration checkpoint

Candidate revision: `156fbb9c675ca9641f6559922b7025a0f2ee8125` from
https://github.com/sz3/libcimbar . This is a reproducible evaluation, not an
Android integration or a completed license clearance.

## Dependency findings from source

| Component | License evidence inspected | Integration disposition |
| --- | --- | --- |
| libcimbar code | MPL-2.0 root LICENSE and file headers | Separate covered component; source availability, modifications and notices must be provided when distributing |
| libcorrect | BSD-3-Clause LICENSE | Retain notice; uses its own RS/convolutional code |
| wirehair / bundled gf256 | BSD-3-Clause LICENSE and gf256 file header | Retain both notices |
| zstd | BSD LICENSE and GPL alternative COPYING | Select BSD option; do not select GPL alternative |
| base91 | zlib-style permission in LICENSE | Preserve origin and modification notices |
| intx | Apache-2.0 LICENSE | Preserve license/required notices |
| libpopcnt | BSD-2-Clause LICENSE | Retain notice |
| concurrentqueue / fmt / PicoSHA2 | Individual license files captured in manifest | Complete inclusion/reachability review before shipping |
| stb | MIT / public-domain alternatives | Select MIT and preserve notice |
| Catch2 | Boost license header in test/catch.hpp | Evaluation-only test dependency |
| OpenCV | External host dependency, not part of vendored snapshot | Pin/review Android build configuration and included codecs separately |
| GLFW / GL | Host build prerequisites | Keep out of planned Android codec target unless actually required |

`tools/cimbar/source.json` records the inspected license-file SHA-256 values.
It is an inventory, not proof that every source file shares a root license.

## Evaluation

The dedicated workflow builds the pinned upstream `encoder_test` target and runs
its fountain padding and streaming round trips through actual colored images.
The upstream implementation is downloaded to a disposable build directory,
not copied into ViaDrop or relicensed. No user content is transmitted.
A successful result proves only host compilation and synthetic image decoding.
It does not prove on-phone CPU performance, optical robustness or patent clearance.

## Android boundary to implement after evaluation

- A dedicated native codec component, with its covered source and changes tracked.
- An original adapter with explicit image dimensions, row stride, RGB/YUV format,
  bounded allocations and a cancellation generation. JNI exceptions must not cross
  into Flutter unchecked.
- Camera pixel access is required: the existing MobileScanner barcode strings
  cannot decode CIMBAR. Do not advertise color support until pixel capture and
  both sender/receiver have been implemented and tested.
- Keep file acceptance, streaming storage, SHA-256 verification and consent in
  ViaDrop; do not use upstream filename-writing helpers on untrusted payloads.
- Publish the exact covered-source archive and notices alongside any distributed
  codec binary, and assess every selected dependency. Do not assume a wrapper
  removes license obligations. ViaDrop-specific independent files remain separate.

Primary license guidance: https://www.mozilla.org/en-US/MPL/2.0/FAQ/ .

## Recorded host result — 2026-10-25

GitHub Actions run https://github.com/MahmoudAbiad/ViaDrop/actions/runs/40186728560
completed successfully for checkpoint a22f023. The pinned `encoder_test` executable
reported **17 assertions passed in 2 test cases**, covering fountain padding and
streaming via color images. No camera, Android device or throughput was tested.

Compiler/linker warnings require follow-up before shipping: an upstream test
helper uses `tmpnam`; the bundled zstd header/filename path triggered a GCC
`-Wstringop-overflow` warning after inlining. These warnings are not confirmed
exploitable vulnerabilities. Investigate with bounded malformed-input tests and
sanitizers; avoid importing the filename/decompression sink into ViaDrop. Prefer
updating or replacing the affected dependency/path with regression coverage.
No new APK contains CIMBAR at this checkpoint.
