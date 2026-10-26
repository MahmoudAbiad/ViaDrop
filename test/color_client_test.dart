import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/engines/color_optical.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const eventMethods = MethodChannel('app.viadrop/color-events');
  tearDown(() {
    messenger.setMockMethodCallHandler(ColorOptical.methods, null);
    messenger.setMockMethodCallHandler(eventMethods, null);
  });

  test('all operations carry the same per-screen identity, including pre-start cancel', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(ColorOptical.methods, (call) async {
      calls.add(call);
      if (call.method == 'senderStart' || call.method == 'receiverStart') {
        return {'generation': 123, 'textureId': 4};
      }
      if (call.method == 'senderFrame') return true;
      return null;
    });
    final first = ColorOpticalClient(), second = ColorOpticalClient();
    await first.stop(); // client is known even before a native start replies
    await first.startSender();
    await first.present(Uint8List.fromList([1, 2, 3]));
    await first.stop();
    final firstId = (calls.first.arguments as Map)['clientId'];
    expect(firstId, greaterThan(0));
    for (final call in calls) {
      expect((call.arguments as Map)['clientId'], firstId);
    }
    await second.startReceiver('bt709');
    expect((calls.last.arguments as Map)['clientId'], isNot(firstId));
    expect((calls.last.arguments as Map)['matrix'], 'bt709');
  });
  test('cancelling an old observer preserves the shared handler for the new screen', () async {
    final controls = <MethodCall>[];
    messenger.setMockMethodCallHandler(eventMethods, (call) async {
      controls.add(call); return null;
    });
    final first = ColorOpticalClient(), second = ColorOpticalClient();
    final old = first.events.listen((_) {});
    final current = second.events.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(controls.map((c) => c.method), ['listen']);
    await old.cancel();
    expect(controls.map((c) => c.method), ['listen']);
    await current.cancel();
    expect(controls.map((c) => c.method), ['listen', 'cancel']);
    expect(controls.first.arguments, {'observer': true});
    expect(controls.last.arguments, {'observer': true});
  });
  test('native packets reach only their owning screen, including after an old listener closes', () async {
    final ids = <int>[];
    messenger.setMockMethodCallHandler(ColorOptical.methods, (call) async {
      ids.add((call.arguments as Map)['clientId'] as int); return null;
    });
    messenger.setMockMethodCallHandler(eventMethods, (_) async => null);
    final first = ColorOpticalClient(), second = ColorOpticalClient();
    await first.stop(); await second.stop();
    final oldPackets = <dynamic>[], currentPackets = <dynamic>[];
    final old = first.events.listen(oldPackets.add);
    final current = second.events.listen(currentPackets.add);
    await Future<void>.delayed(Duration.zero);
    void packet(int owner) {
      ServicesBinding.instance.channelBuffers.push(eventMethods.name,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'type': 'packet', 'clientId': owner, 'generation': 7,
          'data': Uint8List.fromList([1, 2, 3]),
        }), (_) {});
    }
    packet(ids.first);
    await Future<void>.delayed(Duration.zero);
    expect(oldPackets, hasLength(1));
    expect(currentPackets, isEmpty);
    await old.cancel();
    packet(ids.last);
    await Future<void>.delayed(Duration.zero);
    expect(currentPackets, hasLength(1));
    expect(oldPackets, hasLength(1));
    await current.cancel();
  });

}
