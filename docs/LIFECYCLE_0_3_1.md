# Lifecycle reliability — 0.3.1

This milestone hardens application session ownership. It does not change the
optical/acoustic wire protocol, increase advertised throughput or establish
physical-device compatibility. Existing 0.3.0 APKs remain unchanged.

## Concrete failures addressed

| Trigger | Previous risk | Current behavior |
| --- | --- | --- |
| Duplicate native sender/receiver start while a transfer is active | The catch block stopped the existing transfer although the rejected call never acquired it | A start acquires a state lease; rollback is allowed only for that lease |
| Old route finishes asynchronous cleanup after a new route starts | A global stop could cancel the new route's camera/display | Starts, frames and stops carry a unique screen client; old-client stop acknowledges without touching the new owner |
| Late receiver-start reply after the same screen starts another transfer | Cleanup of the late reply could stop the newer generation | Late-reply cleanup includes the exact native generation as well as client identity |
| Stop/background/dispose arrive during the same resource cleanup | Repeated 20ms polling could accumulate tasks and delay replies | One cleanup ticket releases resources; concurrent callers join its completion, once each |
| Stop during pending native cleanup or wakelock enable | Preparation could later show an invitation or open reception again | An invalidated startup ticket cannot publish UI; an attempted unpublished wakelock acquisition is released |
| Old camera/audio page releases the wakelock after another page acquires it | Global disable could unlock the newer transfer's screen | One serialized coordinator tracks separate per-screen leases; a stale release removes only its owner |
| Old event listener closes while another screen is observing | Independent platform streams could unregister the newer message handler | A shared platform observer remains subscribed until the last observer closes; client IDs route packet events |
| User starts while a capability refresh is pending | A late probe result could change the selected mode during startup | Start and mode changes remain disabled until the probe finishes |
| Camera start succeeds/stops before its timeout | Pending delayed work retained old session references | The camera-start timeout is removed on ready, error and cleanup |

## Ownership boundaries

- `ColorSessionState` is an original proprietary application class, independent
  of Android and the MPL codec. It runs on one owner thread. A native session's
  client ID and generation have distinct purposes: screen ownership and exact
  active-transfer identity.
- `ColorBridge` has authority to close the current session on actual Android
  pause/disposal. Ordinary notification subscription cancellation does not own
  camera resources; route disposal explicitly stops its client. The embedding's
  null hot-restart cancellation is handled separately.
- `OpticalStartup` guards preparation only. It must be checked before publishing
  the resulting UI. Prepared-screen wakelocks are released by the route's normal
  finish/stop/disposal path.
- `WakeLockCoordinator` is shared by camera and audio pages, serializes plugin
  operations, and recovers its queue after a failed plugin request. A disposed
  lease can release late but cannot acquire again.
- The independently licensed native codec/component is unchanged. No new
  third-party dependency or license obligation was introduced by these fixes.

Flutter references used for event-lifecycle behavior:
https://api.flutter.dev/flutter/services/EventChannel/receiveBroadcastStream.html
https://api.flutter.dev/javadoc/io/flutter/plugin/common/EventChannel.StreamHandler.html

## Regression coverage

`bash tools/test_color_lifecycle.sh` executes the real application state class
on a host JVM. It checks duplicate-start rejection, joined stop replies, stale
callbacks, failure of one reply, restart from a cleanup callback, disposal,
owner-thread enforcement, old-screen stops and same-screen stale generations.
It also simulates 10,000 cycles with 20,000 exactly-once stop completions. When
Android23 is installed it additionally compiles the application helper against
the minimum boot classpath. These are state simulations, not camera tests.

Dart tests exercise delayed native cleanup, cancellation during wakelock enable,
disposal, error/retry, release while enable is pending, cross-screen wakelock
ownership, channel client arguments, shared observer cancellation and packet
routing after an old listener closes. Production widgets use these same classes.

## Further validation

Real Android navigation/background/camera stress, memory/thermal measurements,
and actual two-phone transfers remain unexecuted. Further lifecycle review is
needed for native audio ownership and transfer-manager isolate completion during
route disposal; this milestone does not declare those separate paths audited.
