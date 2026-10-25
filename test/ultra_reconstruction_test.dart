import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/engines/physical.dart';
import 'package:viadrop/engines/qr_codec.dart';
import 'package:viadrop/third_party/onesend/fountain.dart';
import 'package:viadrop/third_party/onesend/protocol.dart';

void main() {
  for (final size in [2400, 2401, 512 * 1024]) {
    test('Ultra reconstructs $size bytes through QR strings with loss and duplicates', () {
      final payload = Uint8List.fromList(List.generate(size, (i) => (i * 97 + i ~/ 13) & 255));
      const id = 99211;
      final encoder = LTEncoder(payload: payload, blockLength: 2400, sessionId: id);
      final decoder = PhysicalDecoder(512 * 1024, expectedSessionId: id);
      Uint8List? complete;
      // Late join; omit 25% of frames, corrupt selected packets, duplicate the
      // rest, and send useful frames in reversed pairs through the QR codec.
      for (var start = 30; start < 6000 && complete == null; start += 2) {
        for (final sequence in [start + 1, start]) {
          if (sequence % 4 == 0) continue;
          final packet = packFrame(FrameHeader(
            sessionId: id, sequence: sequence, blockCount: encoder.blockCount,
            blockLength: 2400, totalLength: size, payloadChecksum: crc32(payload),
          ), encoder.encode(sequence));
          if (sequence % 11 == 0) {
            final bad = Uint8List.fromList(packet);
            bad[40] ^= 1;
            expect(decodeQrCapture(decoder, [encodeQrFrame(bad)]), isNull);
          }
          final qr = encodeQrFrame(packet);
          complete = decodeQrCapture(decoder, ['unrelated', qr, qr]);
          if (complete != null) break;
        }
      }
      expect(complete, orderedEquals(payload));
      expect(decoder.completedBytes, size);
    });
  }

  test('QR decode rejects oversized text before reconstruction and recovers', () {
    final wire = Uint8List(2600);
    expect(decodeQrFrame(encodeQrFrame(wire)), orderedEquals(wire));
    expect(decodeQrFrame(encodeQrFrame(Uint8List(2601))), isNull);
    expect(decodeQrFrame('VDQR:${base64UrlEncode(Uint8List(2601))}'), isNull);
    expect(decodeQrFrame('VDQ2:${List.filled(100000, '0').join()}'), isNull);
    final valid = Uint8List.fromList([1, 2, 3]);
    expect(decodeQrFrame(encodeQrFrame(valid)), orderedEquals(valid));
  });
}
