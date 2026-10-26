import 'dart:async';
import 'package:flutter/services.dart';
import 'color_optical.dart';
class NativeBridge {
 static const methods=MethodChannel('app.viadrop/native');
 static final events=const EventChannel('app.viadrop/events').receiveBroadcastStream().asBroadcastStream();
 static Future<Map<dynamic,dynamic>> probePhysicalCapabilities() async {
  final value = await methods.invokeMethod<dynamic>('physicalCapabilities');
  final map = value is Map ? Map<dynamic,dynamic>.from(value) : <dynamic,dynamic>{};
  map['colorNative'] = await ColorOptical.available();
  return map;
 }
}
