/// Actual wire profiles, ordered from fastest candidate to slowest.
/// "planned" profiles are deliberately never selectable; detecting hardware
/// cannot make an unimplemented codec available.
enum PhysicalMedium { qr, audio }

class PhysicalProfile {
  const PhysicalProfile({
    required this.id,
    required this.medium,
    required this.title,
    required this.description,
    this.implemented = true,
    this.qrFps = 0,
    this.qrBlockBytes = 0,
    this.audioBlockBytes = 0,
    this.audioFast = false,
    this.audioHigh = false,
  });

  final String id, title, description;
  final PhysicalMedium medium;
  final bool implemented, audioFast, audioHigh;
  final int qrFps, qrBlockBytes, audioBlockBytes;
}

const physicalProfiles = <PhysicalProfile>[
  PhysicalProfile(
    id: 'qr-ultra', medium: PhysicalMedium.qr, title: 'Ultra Optical',
    description: 'ترميز بصري متقدم — قيد البحث ولم يُنفّذ بعد',
    implemented: false,
  ),
  PhysicalProfile(
    id: 'qr-dense', medium: PhysicalMedium.qr, title: 'High-Density QR',
    description: 'QR كثيف واستقبال عالي السرعة — لم يُنفّذ بعد',
    implemented: false,
  ),
  PhysicalProfile(
    id: 'qr-fast', medium: PhysicalMedium.qr, title: 'QR Fast • تجريبي',
    description: '7 رموز/ثانية، 320 بايت للإطار. يتطلب كاميرا 30 FPS وشاشة مناسبة',
    qrFps: 7, qrBlockBytes: 320,
  ),
  PhysicalProfile(
    id: 'qr-standard', medium: PhysicalMedium.qr, title: 'QR Standard',
    description: '5 رموز/ثانية، 280 بايت للإطار. الأكثر محافظة',
    qrFps: 5, qrBlockBytes: 280,
  ),
  PhysicalProfile(
    id: 'audio-turbo', medium: PhysicalMedium.audio, title: 'OFDM Turbo',
    description: 'تشكيل صوتي متقدم — لم يُنفّذ بعد',
    implemented: false,
  ),
  PhysicalProfile(
    id: 'audio-ofdm', medium: PhysicalMedium.audio, title: 'OFDM Wideband • تجريبي',
    description: '900 بايت للإطار، صوت مسموع عريض النطاق',
    audioBlockBytes: 900, audioFast: true,
  ),
  PhysicalProfile(
    id: 'audio-audible', medium: PhysicalMedium.audio, title: 'GGWave Audible',
    description: '100 بايت للإطار، صوت مسموع وتوافق أوسع',
    audioBlockBytes: 100,
  ),
  PhysicalProfile(
    id: 'audio-ultrasound', medium: PhysicalMedium.audio,
    title: 'GGWave High Frequency • تجريبي',
    description: '100 بايت للإطار، يحتاج سماعة وميكروفون يدعمان الترددات العالية',
    audioBlockBytes: 100, audioHigh: true,
  ),
];

PhysicalProfile? physicalProfileById(String id) {
  for (final profile in physicalProfiles) {
    if (profile.id == id) return profile;
  }
  return null;
}

class ProfileAvailability {
  const ProfileAvailability(this.enabled, this.reason);
  final bool enabled;
  final String reason;
}

/// A hardware probe is only a *candidate* check, not a physical link test.
/// Unsupported, unknown and not-yet-implemented profiles are disabled.
class PhysicalCapabilities {
  const PhysicalCapabilities({
    required this.probeOk,
    required this.camera,
    required this.cameraMaxFps,
    required this.displayHz,
    required this.microphone,
    required this.audioInput48k,
    required this.audioOutput48k,
    required this.ofdmNative,
    required this.ultrasoundInput,
    required this.ultrasoundOutput,
  });

  const PhysicalCapabilities.unavailable()
      : probeOk = false, camera = false, cameraMaxFps = 0,
        displayHz = 0, microphone = false, audioInput48k = false,
        audioOutput48k = false, ofdmNative = false,
        ultrasoundInput = false, ultrasoundOutput = false;

  final bool probeOk, camera, microphone, audioInput48k, audioOutput48k;
  final bool ofdmNative, ultrasoundInput, ultrasoundOutput;
  final int cameraMaxFps;
  final double displayHz;

  factory PhysicalCapabilities.fromMap(Map<dynamic, dynamic> m) =>
      PhysicalCapabilities(
        probeOk: m['probeOk'] == true,
        camera: m['camera'] == true,
        cameraMaxFps: (m['cameraMaxFps'] as num?)?.toInt() ?? 0,
        displayHz: (m['displayHz'] as num?)?.toDouble() ?? 0,
        microphone: m['microphone'] == true,
        audioInput48k: m['audioInput48k'] == true,
        audioOutput48k: m['audioOutput48k'] == true,
        ofdmNative: m['ofdmNative'] == true,
        ultrasoundInput: m['ultrasoundInput'] == true,
        ultrasoundOutput: m['ultrasoundOutput'] == true,
      );

  ProfileAvailability availability(PhysicalProfile p) {
    if (!p.implemented) {
      return const ProfileAvailability(false, 'غير منفّذ في هذا الإصدار');
    }
    if (!probeOk) {
      return const ProfileAvailability(false, 'تعذر فحص الجهاز — أعد الفحص');
    }
    if (p.medium == PhysicalMedium.qr) {
      if (!camera) {
        return const ProfileAvailability(false, 'لا توجد كاميرا متاحة');
      }
      if (p.id == 'qr-fast' &&
          (cameraMaxFps < 30 || displayHz < 50)) {
        return const ProfileAvailability(
          false, 'تحتاج كاميرا 30 FPS وشاشة 50 Hz على الأقل',
        );
      }
      return const ProfileAvailability(
        true, 'مرشح تقنياً • يحتاج تجربة حقيقية مع الجهاز الآخر',
      );
    }
    if (!microphone || !audioInput48k || !audioOutput48k) {
      return const ProfileAvailability(
        false, 'الميكروفون أو تشغيل/تسجيل PCM 48 kHz غير متاح',
      );
    }
    if (p.audioFast && !ofdmNative) {
      return const ProfileAvailability(false, 'مودم OFDM الأصلي غير متاح');
    }
    if (p.audioHigh && (!ultrasoundInput || !ultrasoundOutput)) {
      return const ProfileAvailability(
        false, 'دعم الميكروفون/السماعة للترددات العالية غير مُثبت',
      );
    }
    return const ProfileAvailability(
      true, 'مرشح تقنياً • يحتاج تجربة صوتية فعلية بين هاتفين',
    );
  }

  /// The "best for my phone" default is the fastest *eligible* implemented
  /// mode. Two phones might pick different modes; never assume mutual support.
  PhysicalProfile? recommended(PhysicalMedium medium) {
    for (final p in physicalProfiles) {
      if (p.medium == medium && availability(p).enabled) return p;
    }
    return null;
  }
}
