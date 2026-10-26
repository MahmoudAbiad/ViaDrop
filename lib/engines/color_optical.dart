import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Pixels and bytes only. No socket, IP or radio fallback.
class ColorOptical {
  static const methods = MethodChannel('app.viadrop/color');

  static Future<bool> available() async {
    try { return await methods.invokeMethod<bool>('probe') ?? false; }
    on PlatformException { return false; }
    on MissingPluginException { return false; }
  }
}

/// Every screen gets its own identity BEFORE asynchronous native startup.
/// A disposed screen's delayed finally/stop cannot cancel a newer screen.
class ColorOpticalClient {
  static int _nextClient = 0;
  final int _client = ++_nextClient;
  late final events = const EventChannel('app.viadrop/color-events')
      .receiveBroadcastStream({'clientId': _client});

  Future<Map<dynamic, dynamic>> startSender() async =>
      (await ColorOptical.methods.invokeMapMethod<dynamic, dynamic>(
        'senderStart', {'clientId': _client}))!;
  Future<Map<dynamic, dynamic>> startReceiver(String matrix) async =>
      (await ColorOptical.methods.invokeMapMethod<dynamic, dynamic>(
        'receiverStart', {'clientId': _client, 'matrix': matrix}))!;
  Future<void> present(Uint8List packet) async {
    if (await ColorOptical.methods.invokeMethod<bool>('senderFrame',
        {'clientId': _client, 'data': packet}) != true) {
      throw StateError('Color renderer is busy; packet was not presented');
    }
  }
  Future<void> stop() async => ColorOptical.methods.invokeMethod<void>(
      'stop', {'clientId': _client});
}
