import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Pixels and bytes only. This bridge contains no socket, IP or radio fallback.
class ColorOptical {
  static const methods = MethodChannel('app.viadrop/color');
  static final events = const EventChannel('app.viadrop/color-events')
      .receiveBroadcastStream().asBroadcastStream();

  static Future<bool> available() async {
    try { return await methods.invokeMethod<bool>('probe') ?? false; }
    on PlatformException { return false; }
    on MissingPluginException { return false; }
  }
  static Future<Map<dynamic, dynamic>> startSender() async =>
      (await methods.invokeMapMethod<dynamic, dynamic>('senderStart'))!;
  static Future<Map<dynamic, dynamic>> startReceiver(String matrix) async =>
      (await methods.invokeMapMethod<dynamic, dynamic>('receiverStart', {'matrix': matrix}))!;
  static Future<void> present(Uint8List packet) async {
    if (await methods.invokeMethod<bool>('senderFrame', {'data': packet}) != true) {
      throw StateError('Color renderer is busy; packet was not presented');
    }
  }
  static Future<void> stop() async => methods.invokeMethod<void>('stop');
}
