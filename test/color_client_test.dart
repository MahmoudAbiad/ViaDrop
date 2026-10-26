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
  test('event subscription cancellation carries its own screen identity', () async {
    final controls = <MethodCall>[];
    messenger.setMockMethodCallHandler(eventMethods, (call) async {
      controls.add(call); return null;
    });
    final client = ColorOpticalClient();
    final sub = client.events.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(controls.map((c) => c.method), ['listen', 'cancel']);
    final id = (controls.first.arguments as Map)['clientId'];
    expect(id, greaterThan(0));
    expect((controls.last.arguments as Map)['clientId'], id);
  });

}
