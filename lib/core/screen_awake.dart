import 'package:wakelock_plus/wakelock_plus.dart';

/// Serializes the physical wakelock and counts screen owners. A stale release
/// removes only its own lease and cannot turn off another transfer's lock.
class WakeLockCoordinator {
  WakeLockCoordinator(this._toggle);
  final Future<void> Function(bool enabled) _toggle;
  final Set<Object> _owners = {};
  Future<void> _tail = Future<void>.value();
  bool? _applied;

  WakeLockLease lease() => WakeLockLease._(this);

  Future<void> _set(Object owner, bool active) {
    if (active) { _owners.add(owner); } else { _owners.remove(owner); }
    final operation = _tail.then((_) async {
      final desired = _owners.isNotEmpty;
      if (_applied == desired) return;
      try { await _toggle(desired); _applied = desired; }
      catch (_) { _applied = null; rethrow; }
    });
    // A plugin failure must not poison the serial queue for all future screens.
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }
}

class WakeLockLease {
  WakeLockLease._(this._coordinator);
  final WakeLockCoordinator _coordinator;
  final Object _owner = Object();
  bool _disposed = false;

  Future<void> acquire() {
    if (_disposed) return Future.error(StateError('Screen-awake lease disposed'));
    return _coordinator._set(_owner, true);
  }
  Future<void> release() => _coordinator._set(_owner, false);
  Future<void> dispose() { _disposed = true; return release(); }
}

class ScreenAwake {
  static final _shared = WakeLockCoordinator((enabled) =>
      enabled ? WakelockPlus.enable() : WakelockPlus.disable());
  static WakeLockLease lease() => _shared.lease();
}
