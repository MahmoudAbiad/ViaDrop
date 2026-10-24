import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/core/transfer.dart';
import 'package:viadrop/core/vault.dart';

void main() {
  test('recommend prioritizes available channels', () {
    expect(recommend(100, {Channel.wifi, Channel.audio}), Channel.wifi);
    expect(recommend(100, {Channel.audio, Channel.qr}), Channel.audio);
    expect(recommend(900000, {Channel.bluetooth, Channel.qr}), Channel.bluetooth);
    expect(() => recommend(900000, {Channel.qr}), throwsStateError);
  });

  test('session state accepts valid and rejects invalid transitions', () {
    final session = SessionState();
    expect(() => session.transition(Phase.completed), throwsStateError);
    session.transition(Phase.preparing);
    session.transition(Phase.transferring);
    session.transition(Phase.completed);
    expect(session.phase, Phase.completed);
  });

  test('safeName removes unsafe path characters', () {
    final name = safeName('../unsafe\\:file.txt');
    expect(name.contains('/'), false);
    expect(name.contains('\\'), false);
    expect(name.contains(':'), false);
    expect(name.startsWith('..'), false);
  });

  test('vault restores the encrypted original byte-for-byte', () async {
    final dir = await Directory.systemTemp.createTemp('viadrop-test-');
    try {
      final original = File('${dir.path}/sample.bin');
      final bytes = List<int>.generate(100003, (i) => (i * 13) % 256);
      await original.writeAsBytes(bytes);
      final encrypted = File('${dir.path}/sample.vdp');
      await Vault.seal(original, encrypted, 'a-long-testing-secret-123', CancelToken());
      final restored = await Vault.open(
        encrypted, Directory('${dir.path}/received'), 'a-long-testing-secret-123', CancelToken(),
      );
      expect(await restored.readAsBytes(), bytes);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
