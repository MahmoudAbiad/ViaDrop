import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/core/transfer.dart';
import 'package:viadrop/engines/audio_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const eventMethods = MethodChannel('app.viadrop/audio-events');
  tearDown(() {
    messenger.setMockMethodCallHandler(AudioClient.methods, null);
    messenger.setMockMethodCallHandler(eventMethods, null);
  });
  test('cancel while permission is pending never opens microphone after grant', () async {
    final grant = Completer<bool>(); final calls = <String>[];
    messenger.setMockMethodCallHandler(AudioClient.methods, (call) async { calls.add(call.method); return null; });
    final client = AudioClient(microphonePermission: () => grant.future);
    final opening = client.listen();
    final cancelled = expectLater(opening, throwsA(isA<TransferCancelled>()));
    await client.stop(); grant.complete(true); await cancelled;
    expect(calls, ['stop']);
  });
  test('denied permission never invokes native recorder', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(AudioClient.methods, (call) async { calls.add(call.method); return null; });
    final client = AudioClient(microphonePermission: () async => false);
    await expectLater(client.listen(), throwsStateError);
    expect(calls, isEmpty);
  });
  test('late native ready reply cannot resurrect a cancelled session', () async {
    final ready = Completer<Map<String, int>>(); final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(AudioClient.methods, (call) async {
      calls.add(call);
      return call.method == 'listen' ? ready.future : null;
    });
    final client = AudioClient(microphonePermission: () async => true);
    final opening = client.listen();
    final cancelled = expectLater(opening, throwsA(isA<TransferCancelled>()));
    await Future<void>.delayed(Duration.zero);
    await client.stop(); ready.complete({'generation': 1}); await cancelled;
    expect(calls.map((c) => c.method), ['listen', 'stop']);
    expect((calls.first.arguments as Map)['clientId'], (calls.last.arguments as Map)['clientId']);
  });
  test('sender needs no microphone permission; cancelled playback cannot queue another packet', () async {
    final playing = Completer<void>(); final methods = <String>[];
    messenger.setMockMethodCallHandler(AudioClient.methods, (call) async {
      methods.add(call.method);
      if (call.method == 'openSend') return {'generation': 4};
      if (call.method == 'play') return playing.future;
      return null;
    });
    final client = AudioClient(microphonePermission: () async { fail('Sender requested microphone'); });
    await client.openSender();
    final playback = client.play(Uint8List.fromList([1, 2, 3]), false);
    final cancelled = expectLater(playback, throwsA(isA<TransferCancelled>()));
    await client.stop(); playing.complete(); await cancelled;
    await expectLater(client.play(Uint8List(1), false), throwsA(isA<TransferCancelled>()));
    expect(methods, ['openSend', 'play', 'stop']);
  });
  test('duplicate stop callers join the same native cleanup completion', () async {
    final released = Completer<void>(); var stops = 0, done = false;
    messenger.setMockMethodCallHandler(AudioClient.methods, (call) async {
      if (call.method == 'stop') { stops++; await released.future; }
      return null;
    });
    final client = AudioClient();
    final first = client.stop(), second = client.stop();
    unawaited(first.then((_) => done = true));
    await Future<void>.delayed(Duration.zero);
    expect(stops, 1); expect(done, isFalse); expect(identical(first, second), isTrue);
    released.complete(); await first; await second; expect(done, isTrue);
  });
  test('late old-client cleanup and events cannot target the new client', () async {
    final ids = <int>[];
    messenger.setMockMethodCallHandler(AudioClient.methods, (call) async {
      ids.add((call.arguments as Map)['clientId'] as int);
      return call.method == 'openSend' ? {'generation': 8} : null;
    });
    messenger.setMockMethodCallHandler(eventMethods, (_) async => null);
    final old = AudioClient(), current = AudioClient();
    await old.openSender(); await current.openSender();
    final oldId = ids[0], currentId = ids[1];
    expect(currentId, isNot(oldId));
    final received = <dynamic>[];
    final sub = current.events.listen(received.add);
    await Future<void>.delayed(Duration.zero);
    void emit(int id, int generation) => ServicesBinding.instance.channelBuffers.push(eventMethods.name,
      const StandardMethodCodec().encodeSuccessEnvelope({'clientId': id, 'generation': generation, 'type': 'audioData', 'data': Uint8List(1)}), (_) {});
    emit(oldId, 8); emit(currentId, 7); emit(currentId, 8);
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));
    await old.stop(); expect(ids.last, oldId);
    await sub.cancel(); await current.stop();
  });
  test('native background cancellation prevents all subsequent playback', () async {
    messenger.setMockMethodCallHandler(AudioClient.methods, (call) async {
      if (call.method == 'openSend') return {'generation': 10};
      if (call.method == 'play') throw PlatformException(code: 'AUDIO_CANCELLED');
      return null;
    });
    final client = AudioClient(); await client.openSender();
    await expectLater(client.play(Uint8List(1), false), throwsA(isA<TransferCancelled>()));
    expect(client.cancelled, isTrue);
    await expectLater(client.play(Uint8List(1), false), throwsA(isA<TransferCancelled>()));
    await client.stop();
  });

}
