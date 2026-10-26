import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viadrop/core/manager.dart';
import 'package:viadrop/core/transfer.dart';
import 'package:viadrop/core/vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late TransferManager manager;
  late File input;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('viadrop-manager-cancel-');
    manager = TransferManager();
    manager.work = await Directory('${root.path}/work').create();
    manager.received = await Directory('${root.path}/received').create();
    input = await File('${root.path}/source.txt').writeAsString('ملف تجريبي • ViaDrop');
  });
  tearDown(() async { manager.dispose(); await root.delete(recursive: true); });
  test('dispose during encryption suppresses result and deletes temporary ciphertext', () async {
    manager.begin();
    final preparing = manager.prepare(input, 'test-secret');
    manager.dispose();
    await expectLater(preparing, throwsA(isA<TransferCancelled>()));
    expect(await manager.work.list().toList(), isEmpty);
    expect(await input.exists(), isTrue);
    expect(() => manager.begin(), throwsA(isA<TransferCancelled>()));
  });
  test('an older encryption result cannot become part of a new operation', () async {
    manager.begin();
    final preparing = manager.prepare(input, 'test-secret');
    manager.begin(); final newer = manager.token;
    await expectLater(preparing, throwsA(isA<TransferCancelled>()));
    expect(identical(manager.token, newer), isTrue);
    expect(newer.cancelled, isFalse);
    expect(manager.state.phase, Phase.preparing);
    expect(await manager.work.list().toList(), isEmpty);
  });
  test('dispose during verification never publishes an accepted file or history', () async {
    final envelope = File('${root.path}/source.vdp');
    await Vault.seal(input, envelope, 'test-secret', CancelToken());
    manager.begin();
    final accepting = manager.accept(envelope, 'test-secret', Channel.audio);
    manager.dispose();
    await expectLater(accepting, throwsA(isA<TransferCancelled>()));
    expect(await manager.received.list().toList(), isEmpty);
    expect(manager.history, isEmpty);
    expect((await SharedPreferences.getInstance()).getString('history'), isNull);
  });
}
