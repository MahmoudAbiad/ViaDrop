import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/core/screen_awake.dart';

void main() {
  test('old screen releases cannot turn off a newer transfer wakelock', () async {
    final changes = <bool>[];
    final coordinator = WakeLockCoordinator((on) async { changes.add(on); });
    final old = coordinator.lease(), current = coordinator.lease();
    await old.acquire();
    await current.acquire();
    await old.dispose();
    await old.release(); // delayed finally from a disposed camera page
    expect(changes, [true]);
    await current.release();
    expect(changes, [true, false]);
    await expectLater(old.acquire(), throwsStateError);
  });

  test('release during a pending enable is serialized and leaves screen unlocked', () async {
    final enabling = Completer<void>();
    final changes = <bool>[];
    final coordinator = WakeLockCoordinator((on) async {
      changes.add(on);
      if (on) await enabling.future;
    });
    final lease = coordinator.lease();
    final acquiring = lease.acquire();
    await Future<void>.delayed(Duration.zero);
    final releasing = lease.release();
    expect(changes, [true]);
    enabling.complete();
    await acquiring; await releasing;
    expect(changes, [true, false]);
  });

  test('a failed plugin operation does not poison subsequent cleanup or acquire', () async {
    var first = true;
    final changes = <bool>[];
    final coordinator = WakeLockCoordinator((on) async {
      changes.add(on);
      if (first) { first = false; throw StateError('plugin channel failed'); }
    });
    final lease = coordinator.lease();
    await expectLater(lease.acquire(), throwsStateError);
    await lease.release();
    await lease.acquire();
    await lease.dispose();
    expect(changes, [true, false, true, false]);
  });
}
