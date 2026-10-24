import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/engines/physical.dart';
import 'package:viadrop/third_party/onesend/fountain.dart';
import 'package:viadrop/third_party/onesend/protocol.dart';

void main() {
  test('receive metrics count valid and rejected frames and record goodput',
      () async {
    final payload = Uint8List.fromList(List<int>.generate(160, (i) => i));
    const id = 98989;
    final encoder = LTEncoder(
      payload: payload, blockLength: 80, sessionId: id,
    );
    Uint8List frame(int seq, {int session = id}) => packFrame(
      FrameHeader(
        sessionId: session,
        sequence: seq,
        blockCount: encoder.blockCount,
        blockLength: 80,
        totalLength: payload.length,
        payloadChecksum: crc32(payload),
      ),
      encoder.encode(seq),
    );
    final decoder = PhysicalDecoder(1024, expectedSessionId: id);
    expect(decoder.add(frame(0, session: id + 1)), isNull);
    expect(decoder.rejectedFrames, 1);
    expect(decoder.validFrames, 0);

    expect(decoder.add(frame(0)), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final complete = decoder.add(frame(1));
    expect(complete, orderedEquals(payload));
    expect(decoder.completedBytes, payload.length);
    expect(decoder.validFrames, 2);
    expect(decoder.rejectedFrames, 1);
    expect(decoder.payloadKiBPerSecond, greaterThan(0));
    expect(decoder.receivedFramesPerSecond, greaterThan(0));
  });
}
