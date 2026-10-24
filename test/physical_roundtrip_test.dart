import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/engines/physical.dart';
import 'package:viadrop/third_party/onesend/fountain.dart';
import 'package:viadrop/third_party/onesend/protocol.dart';

void main() {
  test('QR fountain transport restores complete bytes despite lost frames', () {
    final payload = Uint8List.fromList(
      List<int>.generate(931, (index) => (index * 17 + 9) % 256),
    );
    const id = 0x1234567;
    const blockLength = 90;
    final encoder = LTEncoder(
      payload: payload,
      blockLength: blockLength,
      sessionId: id,
    );
    final receiver = PhysicalDecoder(2048);
    Uint8List? complete;
    // Simulate losing 20% of camera frames and out-of-order initial capture.
    for (var sequence = 8; sequence < 500 && complete == null; sequence++) {
      if (sequence % 5 == 0) continue;
      final frame = packFrame(
        FrameHeader(
          sessionId: id,
          sequence: sequence,
          blockCount: encoder.blockCount,
          blockLength: blockLength,
          totalLength: payload.length,
          payloadChecksum: crc32(payload),
        ),
        encoder.encode(sequence),
      );
      complete = receiver.add(frame);
      if (complete == null) {
        // The decoder should ignore duplicate camera frames.
        complete = receiver.add(frame);
      }
    }
    expect(complete, isNotNull);
    expect(complete, orderedEquals(payload));
  });

  test('corrupt QR frame is rejected before it can affect reconstruction', () {
    final payload = Uint8List.fromList(List<int>.generate(140, (i) => i));
    final encoder = LTEncoder(payload: payload, blockLength: 70, sessionId: 17);
    final frame = packFrame(
      FrameHeader(
        sessionId: 17,
        sequence: 0,
        blockCount: encoder.blockCount,
        blockLength: 70,
        totalLength: payload.length,
        payloadChecksum: crc32(payload),
      ),
      encoder.encode(0),
    );
    final bad = Uint8List.fromList(frame);
    bad[bad.length - 1] ^= 0xff;
    final decoder = PhysicalDecoder(2048);
    expect(decoder.add(bad), isNull);
    expect(decoder.progress, 0);
    expect(decoder.add(frame), isNull); // Only one of two source blocks.
    expect(decoder.progress, greaterThan(0));
  });
}
