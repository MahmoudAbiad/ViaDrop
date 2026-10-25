import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/core/transfer.dart';
import 'package:viadrop/engines/physical.dart';
import 'package:viadrop/engines/qr_codec.dart';
import 'package:viadrop/third_party/onesend/protocol.dart';

void main() {
  test('multi QR batches carry four distinct packets and reconstruct with tile loss', () async {
    final dir = await Directory.systemTemp.createTemp('viadrop-grid-');
    final token = CancelToken();
    try {
      final data = Uint8List.fromList(List.generate(15003, (i) => (i * 31 + i ~/ 7) & 255));
      final file = await File('${dir.path}/payload').writeAsBytes(data);
      final decoder = PhysicalDecoder(512 * 1024, expectedSessionId: 1729);
      Uint8List? complete;
      var batches = 0;
      final engine = PhysicalEngine(Channel.qr, sessionId: 1729,
        emit: (_) async => fail('Grid must render atomically through emitBatch'),
        emitBatch: (packets) async {
          batches++;
          expect(packets.length, 4);
          expect(packets.map((p) => parseFrame(p)!.header.sequence).toSet().length, 4);
          // Model a camera that misses one tile and reports the other three
          // in reverse order. All tiles feed the same reconstruction session.
          complete = decodeQrCapture(decoder, packets.skip(1).map(encodeQrFrame).toList().reversed);
          if (complete != null || batches > 200) token.cancelled = true;
        },
      )..qrTiles = 4 ..fps = 120 ..blockLength = 512;
      await expectLater(engine.send(file, null, token, (_, __) {}), throwsA(isA<TransferCancelled>()));
      expect(complete, orderedEquals(data));
    } finally {
      token.cancelled = true;
      await dir.delete(recursive: true);
    }
  });
}
