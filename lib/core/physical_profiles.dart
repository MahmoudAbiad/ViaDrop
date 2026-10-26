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
    this.color = false,
    this.qrFps = 0,
    this.qrBlockBytes = 0,
    this.qrVersion = 13,
    this.qrTiles = 1,
    this.audioBlockBytes = 0,
    this.audioFrameGapMs = 180,
    this.audioFast = false,
    this.audioHigh = false,
  });

  final String id, title, description;
  final PhysicalMedium medium;
  final bool implemented, color, audioFast, audioHigh;
  final int qrFps, qrBlockBytes, qrVersion, qrTiles, audioBlockBytes, audioFrameGapMs;
}

const physicalProfiles = <PhysicalProfile>[
  PhysicalProfile(
    id: 'qr-ultra', medium: PhysicalMedium.qr,
    title: 'Ultra Optical • مختبري',
    description: 'QR إصدار 40: حمولة 2400 بايت وإرسال 30 رمزاً/ثانية. يتطلب شاشة عالية الدقة، كاميرا سريعة، واختبار استقبال فعلي.',
    qrFps: 30, qrBlockBytes: 2400, qrVersion: 40,
  ),
  PhysicalProfile(
    id: 'qr-color', medium: PhysicalMedium.qr, color: true,
    title: 'CIMBAR Color • تجريبي',
    description: 'بيانات فعلية بالألوان، 2400 بايت/إطار حتى 10 تحديثات/ثانية حسب الترميز. يتطلب شاشة 1080px وكاميرا مناسبة؛ سرعة الاستقبال غير مختبرة.',
    qrFps: 10, qrBlockBytes: 2400,
  ),
  PhysicalProfile(
    id: 'qr-grid', medium: PhysicalMedium.qr,
    title: 'Multi-QR 2×2 • مختبري',
    description: 'أربعة رموز مستقلة في الشاشة، 512 بايت لكل رمز و10 تحديثات/ثانية. قد يكون أبطأ إذا صعب مسح الرموز الصغيرة؛ لا توجد سرعة مضمونة.',
    qrFps: 10, qrBlockBytes: 512, qrVersion: 17, qrTiles: 4,
  ),
  PhysicalProfile(
    id: 'qr-dense', medium: PhysicalMedium.qr,
    title: 'High-Density QR • تجريبي',
    description: '512 بايت/رمز QR الإصدار 17، حتى 9 رموز/ثانية. يحتاج كاميرا 30 FPS وشاشة 60 Hz؛ نجاح المسح غير مضمون.',
    qrFps: 9, qrBlockBytes: 512, qrVersion: 17,
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
    id: 'audio-turbo', medium: PhysicalMedium.audio,
    title: 'OFDM Turbo • تجريبي',
    description: 'مودم OFDM الحالي بفاصل 40ms بدلاً من 180ms بين الإطارات، يحتاج هاتف حديثاً؛ لا يتضمن تشكيلاً صوتياً جديداً',
    audioBlockBytes: 900, audioFast: true, audioFrameGapMs: 40,
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
    this.colorNative = false,
    this.androidSdk = 0,
    this.processorCores = 0,
    this.displayWidthPx = 0,
    required this.ultrasoundInput,
    required this.ultrasoundOutput,
  });

  const PhysicalCapabilities.unavailable()
      : probeOk = false, camera = false, cameraMaxFps = 0, colorNative = false,
        displayHz = 0, microphone = false, audioInput48k = false,
        audioOutput48k = false, ofdmNative = false,
        ultrasoundInput = false, ultrasoundOutput = false,
        androidSdk = 0, processorCores = 0, displayWidthPx = 0;

  final bool probeOk, camera, microphone, audioInput48k, audioOutput48k;
  final int androidSdk, processorCores, displayWidthPx;
  final bool ofdmNative, colorNative, ultrasoundInput, ultrasoundOutput;
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
        colorNative: m['colorNative'] == true,
        androidSdk: (m['androidSdk'] as num?)?.toInt() ?? 0,
        processorCores: (m['processorCores'] as num?)?.toInt() ?? 0,
        displayWidthPx: (m['displayWidthPx'] as num?)?.toInt() ?? 0,
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
      if (p.color && (!colorNative || displayWidthPx < 1080 ||
          androidSdk < 26 || cameraMaxFps < 30 || processorCores < 4)) {
        return const ProfileAvailability(false,
          'الألوان: تحتاج المحرك الأصلي وAndroid 8+ وشاشة 1080px وكاميرا 30fps وأربع أنوية؛ حجم التقاط الكاميرا يُفحص عند البدء');
      }
      if ((p.id == 'qr-ultra' || p.id == 'qr-grid') &&
          (cameraMaxFps < 30 || displayHz < 59 ||
              displayWidthPx < 900 || androidSdk < 26 ||
              processorCores < 4)) {
        return const ProfileAvailability(
          false, 'Ultra: تحتاج Android 8+ وكاميرا 30fps وشاشة 60Hz بعرض 900px وأربع أنوية على الأقل',
        );
      }
      if (p.id == 'qr-dense' &&
          (cameraMaxFps < 30 || displayHz < 59)) {
        return const ProfileAvailability(
          false, 'QR كثيف: تحتاج كاميرا 30 FPS وشاشة 60 Hz تقريباً',
        );
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
    if (p.id == 'audio-turbo' &&
        (androidSdk < 26 || processorCores < 4)) {
      return const ProfileAvailability(
        false, 'Turbo: يحتاج Android 8 أو أحدث وأربع أنوية على الأقل',
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
