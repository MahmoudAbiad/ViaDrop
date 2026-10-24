import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/core/one_way_session.dart';
import 'package:viadrop/core/transfer.dart';
import 'package:viadrop/core/vault.dart';
import 'package:viadrop/engines/physical.dart';
import 'package:viadrop/third_party/onesend/fountain.dart';
import 'package:viadrop/third_party/onesend/protocol.dart';

void main() {
  test('single one-way start works identically for QR and acoustic start', () {
    final sender = OneWaySession.create();
    final qrReceiver = OneWaySession.parse(sender.announcement);
    final audioReceiver = OneWaySession.parse(
      String.fromCharCodes(sender.audioAnnouncement),
    );
    expect(qrReceiver, isNotNull);
    expect(audioReceiver, isNotNull);
    expect(qrReceiver!.sessionId, sender.sessionId);
    expect(audioReceiver!.sessionId, sender.sessionId);
    expect(qrReceiver.passphrase, sender.passphrase);
    expect(audioReceiver.passphrase, sender.passphrase);
    expect(sender.audioAnnouncement.length, lessThanOrEqualTo(140));
  });

  test('new sessions are independent and malformed announcements are ignored', () {
    final first = OneWaySession.create();
    final second = OneWaySession.create();
    expect(first.passphrase, isNot(second.passphrase));
    expect(OneWaySession.parse('VDPAIR1:00000001:key'), isNull);
    expect(OneWaySession.parse('VDREADY1:00000001:ack'), isNull);
    expect(OneWaySession.parse('VDS2:00000000:${first.passphrase}'), isNull);
    expect(OneWaySession.parse('VDS2:zzzzzzzz:${first.passphrase}'), isNull);
    expect(OneWaySession.parse('VDS2:00000001:not-a-secret'), isNull);
    expect(OneWaySession.parse(first.announcement + ':garbage'), isNull);
  });

  test('one-way session decodes an encrypted QR/audio fountain transfer', () async {
    final dir = await Directory.systemTemp.createTemp('viadrop-one-way-');
    try {
      final sender = OneWaySession.create();
      final receiver = OneWaySession.parse(sender.announcement)!;
      final input = File('${dir.path}/sample.txt');
      await input.writeAsString('نقل ملف من طرف واحد — ViaDrop');
      final sealed = File('${dir.path}/sealed.vdp');
      await Vault.seal(input, sealed, sender.passphrase, CancelToken());
      final data = Uint8List.fromList(await sealed.readAsBytes());
      final encoder = LTEncoder(
        payload: data,
        blockLength: 100,
        sessionId: sender.sessionId,
      );
      final decoder = PhysicalDecoder(
        64 * 1024,
        expectedSessionId: receiver.sessionId,
      );
      Uint8List? received;
      for (var sequence = 0; sequence < 500 && received == null; sequence++) {
        if (sequence % 7 == 0) continue; // Simulate lost optical/acoustic data.
        received = decoder.add(packFrame(
          FrameHeader(
            sessionId: sender.sessionId,
            sequence: sequence,
            blockCount: encoder.blockCount,
            blockLength: 100,
            totalLength: data.length,
            payloadChecksum: crc32(data),
          ),
          encoder.encode(sequence),
        ));
      }
      expect(received, isNotNull);
      final receivedSealed = File('${dir.path}/received.vdp');
      await receivedSealed.writeAsBytes(received!);
      final output = await Vault.open(
        receivedSealed,
        Directory('${dir.path}/out'),
        receiver.passphrase,
        CancelToken(),
      );
      expect(await output.readAsString(), await input.readAsString());
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('one-way session still filters unrelated session frames', () {
    final correct = OneWaySession.create();
    final unrelated = OneWaySession.create();
    final payload = Uint8List.fromList(List<int>.generate(80, (i) => i));
    final encoder = LTEncoder(
      payload: payload,
      blockLength: 80,
      sessionId: unrelated.sessionId,
    );
    final frame = packFrame(FrameHeader(
      sessionId: unrelated.sessionId,
      sequence: 0,
      blockCount: encoder.blockCount,
      blockLength: 80,
      totalLength: payload.length,
      payloadChecksum: crc32(payload),
    ), encoder.encode(0));
    final decoder = PhysicalDecoder(
      1024,
      expectedSessionId: correct.sessionId,
    );
    expect(decoder.add(frame), isNull);
    expect(decoder.header, isNull);
  });
}
