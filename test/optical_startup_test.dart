import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/core/optical_startup.dart';

void main() {
  test('cancel during native cleanup never reacquires wake or publishes receiver', () async {
    final cleanup = Completer<void>();
    final startup = OpticalStartup();
    var wakes = 0;
    final result = startup.prepare(stopNative: () => cleanup.future,
      acquireWake: () async { wakes++; }, releaseWake: () async { wakes--; });
    startup.cancel();
    cleanup.complete();
    expect(await result, isNull);
    expect(wakes, 0);
  });

  test('cancel during wake acquisition releases it before allowing restart', () async {
    final acquired = Completer<void>();
    final released = Completer<void>();
    final startup = OpticalStartup();
    var releases = 0;
    final result = startup.prepare(stopNative: () async {},
      acquireWake: () => acquired.future,
      releaseWake: () { releases++; return released.future; });
    await Future<void>.delayed(Duration.zero);
    startup.cancel();
    acquired.complete();
    await Future<void>.delayed(Duration.zero);
    expect(releases, 1);
    await expectLater(startup.prepare(stopNative: () async {},
      acquireWake: () async {}, releaseWake: () async {}), throwsStateError);
    released.complete();
    expect(await result, isNull);
    final next = await startup.prepare(stopNative: () async {},
      acquireWake: () async {}, releaseWake: () async {});
    expect(next, isNotNull);
    expect(startup.isCurrent(next!), isTrue);
  });

  test('a result cancelled before UI publication is no longer current', () async {
    final startup = OpticalStartup();
    final ticket = await startup.prepare(stopNative: () async {},
      acquireWake: () async {}, releaseWake: () async {});
    expect(startup.isCurrent(ticket!), isTrue);
    startup.cancel();
    expect(startup.isCurrent(ticket), isFalse);
    final another = OpticalStartup();
    expect(another.isCurrent(ticket), isFalse);
  });

  test('startup errors release attempted acquisition and do not poison retry', () async {
    final startup = OpticalStartup();
    var releases = 0;
    await expectLater(startup.prepare(stopNative: () async {},
      acquireWake: () async { throw StateError('wakelock failed'); },
      releaseWake: () async { releases++; }), throwsStateError);
    expect(releases, 1);
    final ticket = await startup.prepare(stopNative: () async {},
      acquireWake: () async {}, releaseWake: () async {});
    expect(ticket, isNotNull);
  });

  test('dispose invalidates pending preparation and rejects later starts', () async {
    final cleanup = Completer<void>();
    final startup = OpticalStartup();
    final result = startup.prepare(stopNative: () => cleanup.future,
      acquireWake: () async { fail('disposed page reacquired wake'); },
      releaseWake: () async {});
    startup.dispose();
    cleanup.complete();
    expect(await result, isNull);
    await expectLater(startup.prepare(stopNative: () async {},
      acquireWake: () async {}, releaseWake: () async {}), throwsStateError);
  });
}
