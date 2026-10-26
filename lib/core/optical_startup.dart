/// Guards UI publication across asynchronous resource preparation. Actual
/// native session ownership and screen-awake leases are managed separately.
class OpticalStartup {
  int _generation = 0;
  bool _preparing = false, _disposed = false;

  bool isCurrent(OpticalStartupTicket ticket) =>
      identical(ticket._owner, this) && !_disposed &&
      ticket._generation == _generation;

  void cancel() { _generation++; }
  void dispose() { _disposed = true; cancel(); }

  Future<OpticalStartupTicket?> prepare({
    required Future<void> Function() stopNative,
    required Future<void> Function() acquireWake,
    required Future<void> Function() releaseWake,
  }) async {
    if (_disposed || _preparing) throw StateError('Optical startup busy or disposed');
    _preparing = true;
    final ticket = OpticalStartupTicket._(this, ++_generation);
    var attemptedWake = false, published = false;
    try {
      await stopNative();
      if (!isCurrent(ticket)) return null;
      attemptedWake = true;
      await acquireWake();
      if (!isCurrent(ticket)) return null;
      published = true;
      return ticket;
    } catch (_) {
      if (!isCurrent(ticket)) return null;
      rethrow;
    } finally {
      try {
        if (attemptedWake && !published) await releaseWake();
      } finally { _preparing = false; }
    }
  }
}

class OpticalStartupTicket {
  const OpticalStartupTicket._(this._owner, this._generation);
  final OpticalStartup _owner;
  final int _generation;
}
