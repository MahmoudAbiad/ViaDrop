import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/transfer.dart';

/// One identity per acoustic operation, assigned BEFORE permission/startup.
/// Cancellation is immediate locally; its future waits for native resource drain.
class AudioClient {
  AudioClient({Future<bool> Function()? microphonePermission})
      : _permission = microphonePermission ?? _requestPermission;
  static const methods = MethodChannel('app.viadrop/audio');
  static final _events = const EventChannel('app.viadrop/audio-events')
      .receiveBroadcastStream(const {'observer': true});
  static int _next = 0;
  final int _id = ++_next;
  final Future<bool> Function() _permission;
  bool _cancelled = false;
  int? _generation;
  Future<void>? _stopping;
  bool get cancelled => _cancelled;
  static Future<bool> _requestPermission() async =>
      (await Permission.microphone.request()).isGranted;
  void check() { if (_cancelled) throw const TransferCancelled(); }

  Stream<dynamic> get events => _events.where((e) => !_cancelled && e is Map &&
      e['clientId'] == _id && (_generation == null || e['generation'] == _generation));

  Future<void> _start(String method, {bool fast = false}) async {
    check();
    try {
      final result = await methods.invokeMapMethod<dynamic, dynamic>(method,
          {'clientId': _id, 'fast': fast});
      check();
      if (result?['generation'] is! int) throw StateError('Invalid native audio start reply');
      _generation = result!['generation'] as int;
    } catch (error) {
      if (error is PlatformException && error.code == 'AUDIO_CANCELLED') _cancelled = true;
      check(); rethrow;
    }
  }
  Future<void> openSender() => _start('openSend');
  Future<void> listen({bool fast = false}) async {
    check();
    final granted = await _permission();
    check(); // A late permission reply must never reopen a cancelled microphone.
    if (!granted) throw StateError('Microphone permission denied');
    await _start('listen', fast: fast);
  }
  Future<void> play(Uint8List bytes, bool high, {bool fast = false}) async {
    check();
    if (_generation == null) throw StateError('Audio sender has not started');
    try {
      await methods.invokeMethod<void>('play',
          {'clientId': _id, 'data': bytes, 'high': high, 'fast': fast});
      check();
    } catch (error) {
      if (error is PlatformException && error.code == 'AUDIO_CANCELLED') _cancelled = true;
      check(); rethrow;
    }
  }
  Future<void> stop() {
    _cancelled = true;
    return _stopping ??= methods.invokeMethod<void>('stop', {'clientId': _id});
  }
}
