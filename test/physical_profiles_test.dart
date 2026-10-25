import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/core/one_way_session.dart';
import 'package:viadrop/core/physical_profiles.dart';

void main() {
  const modern = PhysicalCapabilities(
    probeOk: true, camera: true, cameraMaxFps: 60,
    displayHz: 60, microphone: true,
    audioInput48k: true, audioOutput48k: true,
    ofdmNative: true,
    androidSdk: 33, processorCores: 8, displayWidthPx: 1080,
    ultrasoundInput: false, ultrasoundOutput: false,
  );
  const older = PhysicalCapabilities(
    probeOk: true, camera: true, cameraMaxFps: 15,
    displayHz: 60, microphone: true,
    audioInput48k: true, audioOutput48k: true,
    ofdmNative: false,
    ultrasoundInput: false, ultrasoundOutput: false,
  );

  test('only implemented and provisionally supported modes are selectable', () {
    expect(modern.recommended(PhysicalMedium.qr)?.id, 'qr-ultra');
    expect(modern.recommended(PhysicalMedium.audio)?.id, 'audio-turbo');
    expect(older.recommended(PhysicalMedium.qr)?.id, 'qr-standard');
    expect(older.recommended(PhysicalMedium.audio)?.id, 'audio-audible');

    for (final profile in physicalProfiles.where((p) => !p.implemented)) {
      expect(modern.availability(profile).enabled, isFalse);
    }
    expect(modern.availability(physicalProfileById('audio-ultrasound')!).enabled,
        isFalse);
    expect(older.availability(physicalProfileById('qr-fast')!).enabled, isFalse);
    expect(older.availability(physicalProfileById('qr-dense')!).enabled, isFalse);
    expect(physicalProfileById('qr-dense')!.qrVersion, 17);
    expect(physicalProfileById('qr-dense')!.qrBlockBytes, 512);
    expect(physicalProfileById('qr-ultra')!.qrVersion, 40);
    expect(physicalProfileById('qr-ultra')!.qrBlockBytes, 2400);
    expect(physicalProfileById('qr-ultra')!.qrFps, 30);
    expect(older.availability(physicalProfileById('qr-ultra')!).enabled, isFalse);
    expect(older.availability(physicalProfileById('audio-ofdm')!).enabled, isFalse);
    expect(older.availability(physicalProfileById('audio-turbo')!).enabled, isFalse);
    expect(physicalProfileById('audio-turbo')!.audioFrameGapMs, 40);
    expect(physicalProfileById('audio-ofdm')!.audioFrameGapMs, 180);
  });

  test('unknown or failed probes never enable a transfer mode', () {
    const failed = PhysicalCapabilities.unavailable();
    for (final profile in physicalProfiles) {
      expect(failed.availability(profile).enabled, isFalse);
    }
    expect(failed.recommended(PhysicalMedium.audio), isNull);
    expect(failed.recommended(PhysicalMedium.qr), isNull);
  });

  test('native probe maps do not treat absent fields as device support', () {
    final caps = PhysicalCapabilities.fromMap({
      'probeOk': true, 'camera': true,
      'cameraMaxFps': 30, 'displayHz': 60.0,
    });
    expect(caps.recommended(PhysicalMedium.qr)?.id, 'qr-dense');
    expect(caps.recommended(PhysicalMedium.audio), isNull);
  });

  test('outgoing announcement identifies exact codec on both ends', () {
    for (final profile in physicalProfiles.where((p) => p.implemented)) {
      final sent = OneWaySession.create(profileId: profile.id);
      final received = OneWaySession.parse(sent.announcement);
      expect(received, isNotNull);
      expect(received!.profileId, profile.id);
      expect(received.sessionId, sent.sessionId);
      expect(received.passphrase, sent.passphrase);
      expect(sent.audioAnnouncement.length, lessThanOrEqualTo(140));
    }
    final fast = OneWaySession.create(profileId: 'qr-fast');
    expect(OneWaySession.parse(fast.announcement)!.profileId,
        isNot('qr-standard'));
    expect(OneWaySession.parse(
      fast.announcement.replaceFirst('qr-fast', 'not-a-profile'),
    ), isNull);
    expect(OneWaySession.parse(
      fast.announcement.replaceFirst('VDS3:', 'VDS2:'),
    ), isNull);
    expect(() => OneWaySession.create(profileId: 'not-a-profile'),
        throwsArgumentError);
  });
}
