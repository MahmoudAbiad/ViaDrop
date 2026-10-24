import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/core/qr_pairing.dart';
import 'package:viadrop/core/transfer.dart';
import 'package:viadrop/core/vault.dart';
import 'package:viadrop/engines/physical.dart';
import 'package:viadrop/engines/qr_codec.dart';
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

  for (final channel in [Channel.qr, Channel.audio]) {
    test('encrypted ${channel.name} frames restore the original file end-to-end', () async {
      final directory =
          await Directory.systemTemp.createTemp('viadrop-${channel.name}-e2e-');
      final token = CancelToken();
      try {
        final original = File('${directory.path}/original.bin');
        final content = List<int>.generate(
          channel == Channel.audio ? 64 : 970,
          (i) => (i * 29 + 11) % 256,
        );
        await original.writeAsBytes(content);
        final encrypted = File('${directory.path}/encrypted.vdp');
        const passphrase = 'this-is-an-offline-test-password';
        await Vault.seal(original, encrypted, passphrase, CancelToken());

        final decoder = PhysicalDecoder(
          channel == Channel.audio ? 4096 : 512 * 1024,
        );
        Uint8List? completedEnvelope;
        var frames = 0;
        final engine = PhysicalEngine(
          channel,
          emit: (packet) async {
            frames++;
            // QR capture and acoustic decoding can both lose individual frames.
            if (frames % 9 == 0) return;
            final decoded = decoder.add(packet);
            if (decoded != null) {
              completedEnvelope = decoded;
              token.cancelled = true;
            }
          },
        )
          ..blockLength = 180
          ..fps = 60;

        await expectLater(
          engine.send(encrypted, null, token, (_, __) {}),
          throwsA(isA<TransferCancelled>()),
        );
        expect(frames, greaterThan(0));
        expect(completedEnvelope, isNotNull);
        expect(
          completedEnvelope,
          orderedEquals(await encrypted.readAsBytes()),
        );

        final transported = File('${directory.path}/transported.vdp');
        await transported.writeAsBytes(completedEnvelope!);
        final output = await Vault.open(
          transported,
          Directory('${directory.path}/received'),
          passphrase,
          CancelToken(),
        );
        expect(await output.readAsBytes(), orderedEquals(content));
      } finally {
        token.cancelled = true;
        await directory.delete(recursive: true);
      }
    }, timeout: const Timeout(Duration(seconds: 40)));
  }

  test('QR camera capture decodes every barcode in the batch', () {
    final payload = Uint8List.fromList(
      List<int>.generate(120, (i) => (i * 7 + 3) % 256),
    );
    const sessionId = 125;
    final encoder = LTEncoder(
      payload: payload,
      blockLength: 60,
      sessionId: sessionId,
    );
    String qrFrame(int sequence) => 'VDQR:${base64UrlEncode(packFrame(
      FrameHeader(
        sessionId: sessionId,
        sequence: sequence,
        blockCount: encoder.blockCount,
        blockLength: 60,
        totalLength: payload.length,
        payloadChecksum: crc32(payload),
      ),
      encoder.encode(sequence),
    ))}';

    final decoder = PhysicalDecoder(1024);
    // One camera capture can contain two useful QR codes. In the previous
    // implementation the callback returned after the first incomplete frame.
    final received = decodeQrCapture(decoder, [
      null,
      'unrelated barcode',
      'VDQR:!!!',
      qrFrame(0),
      qrFrame(1),
    ]);
    expect(received, isNotNull);
    expect(received, orderedEquals(payload));
  });

  test('invalid payload checksum resets decoder for a new audio session', () {
    final corruptedPayload = Uint8List.fromList(
      List<int>.generate(120, (index) => (index * 11 + 1) % 256),
    );
    final badEncoder = LTEncoder(
      payload: corruptedPayload,
      blockLength: 60,
      sessionId: 101,
    );
    final invalidChecksum = crc32(corruptedPayload) ^ 1;

    Uint8List frameFor(LTEncoder encoder, Uint8List payload,
        int sessionId, int checksum, int sequence) =>
        packFrame(
          FrameHeader(
            sessionId: sessionId,
            sequence: sequence,
            blockCount: encoder.blockCount,
            blockLength: 60,
            totalLength: payload.length,
            payloadChecksum: checksum,
          ),
          encoder.encode(sequence),
        );

    final receiver = PhysicalDecoder(1024);
    expect(receiver.add(frameFor(
      badEncoder, corruptedPayload, 101, invalidChecksum, 0,
    )), isNull);
    expect(() => receiver.add(frameFor(
      badEncoder, corruptedPayload, 101, invalidChecksum, 1,
    )), throwsFormatException);
    expect(receiver.progress, 0);
    expect(receiver.header, isNull);

    // After a failed burst, a new valid sender must be able to start over
    // without stopping and restarting the microphone or QR camera.
    final newPayload = Uint8List.fromList(
      List<int>.generate(120, (index) => (index * 7 + 9) % 256),
    );
    final goodEncoder = LTEncoder(
      payload: newPayload,
      blockLength: 60,
      sessionId: 202,
    );
    final goodChecksum = crc32(newPayload);
    expect(receiver.add(frameFor(
      goodEncoder, newPayload, 202, goodChecksum, 0,
    )), isNull);
    expect(receiver.add(frameFor(
      goodEncoder, newPayload, 202, goodChecksum, 1,
    )), orderedEquals(newPayload));
  });

  test('optical pairing derives matching keys without a shared password', () async {
    final sender = await OpticalPairing.createSender();
    final receiver = await OpticalPairing.acceptInvitation(sender.invitation);
    expect(receiver, isNotNull);
    expect(sender.passphrase, isNull);
    expect(await sender.acceptReply('VDREPLY1:bad'), isFalse);
    expect(await sender.acceptReply(receiver!.reply), isTrue);
    expect(sender.passphrase, isNotNull);
    expect(sender.passphrase, receiver.passphrase);
    expect(sender.passphrase!.length, greaterThan(12));
  });

  test('Base45 QR frames survive arbitrary bytes and reject malformed data', () {
    for (final size in [1, 2, 3, 10, 96, 313, 512]) {
      final bytes = Uint8List.fromList(
        List<int>.generate(size, (i) => (i * 151 + 19) & 255),
      );
      final frame = encodeQrFrame(bytes);
      expect(decodeQrFrame(frame), orderedEquals(bytes));
    }
    expect(decodeQrFrame('VDQ2:!'), isNull);
    expect(decodeQrFrame('VDQ2:ZZZ'), isNull);
    expect(decodeQrFrame('VDQ2:éé'), isNull);
  });

  test('paired QR decoder refuses frames for other transfer sessions', () {
    final bytes = Uint8List.fromList(List<int>.generate(80, (i) => i));
    final encoder = LTEncoder(payload: bytes, blockLength: 80, sessionId: 71);
    final frame = packFrame(FrameHeader(
      sessionId: 71, sequence: 0, blockCount: encoder.blockCount,
      blockLength: 80, totalLength: bytes.length,
      payloadChecksum: crc32(bytes),
    ), encoder.encode(0));
    final decoder = PhysicalDecoder(1024, expectedSessionId: 72);
    expect(decoder.add(frame), isNull);
    expect(decoder.header, isNull);
    final matched = PhysicalDecoder(1024, expectedSessionId: 71);
    expect(matched.add(frame), orderedEquals(bytes));
  });
}
