# Optical acceleration — evidence and implementation boundaries

## Current work

The existing Ultra path is one monochrome QR-v40 (2400-byte fountain blocks).
The new `qr-grid` experiment atomically emits four distinct QR-v17 packets per
screen update (512-byte block each, 10 updates/s), and the camera's barcode batch
feeds all recognized packets into the same fountain decoder. This is not a
fourfold speed claim. At fixed screen area each tile has fewer pixels; useful
throughput can decrease. Initial advertised block throughput is 20,480 bytes/s
before coding loss, missed scans and UI timing. Measure complete output bytes/time.

No color codec is implemented by this change. A colored foreground on a normal
QR does not constitute color multiplexing. RGB multiplexing needs access to
camera RGB/YUV pixels, calibration and per-channel detection/ECC; the current
barcode-only scanner interface cannot provide that by changing a QR color.

## Primary sources inspected (2026-10-25)

- https://github.com/sz3/libcimbar : color/icon encoding; upstream reports
  850 kbit/s (~106 kB/s), monitor-to-phone. MPL-2.0 implementation, not an MIT
  dependency. Consider an isolated component with covered-source obligations
  and full dependency review; this does not automatically open-source ViaDrop.
- https://github.com/bashalarmistalt/decimen-optical-transfer : current upstream
  declares AGPL-3.0. Do not import its implementation into this product.
  Secondary articles describing an MIT license are not clearance evidence.
- https://github.com/jabcode/jabcode : color/multi-symbol code and ISO reference;
  original implementation license needs isolated integration assessment.
- https://github.com/srlehn/jabcode : experimental independent MIT implementation;
  inspect exact revision, provenance and dependencies before adopting.
- https://doi.org/10.1016/j.pmcj.2014.11.003 : screen-camera channel capacity
  modeling. Theoretical capacity is not phone application goodput.
- https://doi.org/10.1109/IMOC65414.2025.11365743 : color shift keying and spatial
  cells; color use alone does not establish high-rate performance.

## Next measured experiments

1. Compare monochrome Ultra, four-tile QR and conservative QR on identical phones,
   file bytes, geometry and lighting; report full-file verified goodput, not FPS.
2. Add native camera pixel capture and a bounded processing worker before color
   integration. Calibrate channel mixing/white balance and perspective using
   reference cells. Benchmark clean digital frames, blur, noise, angle, and real
   recordings separately.
3. Evaluate compatible existing color codecs first. If implementing a different
   codec independently, keep design/source provenance; no copying or translating
   restricted implementation code. Standard techniques do not imply patent
   clearance; investigate relevant patents before commercial distribution.
4. Rate adaptation, exposure/focus control and ROI sampling require real device
   measurements. Keep unsupported experiments disabled or labeled experimental.

There is no defensible "fastest in the world" claim without a defined device,
channel, test protocol and independent comparison. Wi-Fi, optics and acoustics
must be compared within their own physical constraints.
