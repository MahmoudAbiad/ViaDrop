import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:viadrop/core/physical_profiles.dart';
import 'package:viadrop/engines/qr_codec.dart';
import 'package:viadrop/third_party/onesend/protocol.dart';

void main() {
  for (final profile in physicalProfiles.where(
      (p) => p.medium == PhysicalMedium.qr && p.implemented)) {
    test('${profile.id} QR version ${profile.qrVersion} holds a full data frame',
        () {
      final data = Uint8List.fromList(List<int>.generate(
        profile.qrBlockBytes, (i) => (i * 97 + 41) & 255,
      ));
      const sessionId = 56789;
      final packet = packFrame(FrameHeader(
        sessionId: sessionId,
        sequence: 0,
        blockCount: 1,
        blockLength: data.length,
        totalLength: data.length,
        payloadChecksum: crc32(data),
      ), data);
      final encoded = encodeQrFrame(packet);
      expect(decodeQrFrame(encoded), orderedEquals(packet));
      final qr = QrCode(profile.qrVersion, QrErrorCorrectLevel.L)
        ..addAlphaNumeric(encoded);
      // QrImage performs the actual codeword/mask generation (QrCode.make
      // was removed in qr 3.x). This is not a camera-recognition benchmark.
      final matrix = QrImage(qr);
      expect(matrix.moduleCount, 17 + profile.qrVersion * 4);
    });
  }
}
