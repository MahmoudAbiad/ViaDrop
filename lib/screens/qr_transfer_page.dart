import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:open_filex/open_filex.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/manager.dart';
import '../core/one_way_session.dart';
import '../core/physical_profiles.dart';
import '../engines/native.dart';
import '../widgets/physical_profile_selector.dart';
import '../core/transfer.dart';
import '../engines/physical.dart';
import '../engines/qr_codec.dart';

/// Strictly one-way optical transport: static invitation, then animated data.
/// The receiver scans once; it never displays a reply QR.
class QrTransferPage extends StatefulWidget {
  const QrTransferPage({super.key});

  @override
  State<QrTransferPage> createState() => _QrTransferPageState();
}

class _QrTransferPageState extends State<QrTransferPage> {
  final _manager = TransferManager();

  // QR-only scanner configuration. The default mobile_scanner throttle is
  // intended for ordinary barcodes, not a continuously changing data stream.
  // Keep a less aggressive decoder on old phones and reserve unthrottled
  // scanning for explicitly chosen optical high-throughput profiles.
  final MobileScannerController _standardScanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  final MobileScannerController _streamScanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.unrestricted,
    returnImage: false,
  );
  OneWaySession? _session;
  PhysicalDecoder _decoder = PhysicalDecoder(600 * 1024);
  File? _selected;
  File? _received;
  CancelToken? _sendToken;
  bool _ready = false;
  bool _busy = false;
  bool _sendMode = true;
  bool _showInvite = false;
  bool _scanInvite = false;
  bool _scanData = false;
  bool _sending = false;
  bool _finalizing = false;
  PhysicalCapabilities _capabilities = const PhysicalCapabilities.unavailable();
  String? _profileId;
  bool _probing = true;
  bool _scanBusy = false;
  int _countdown = 0;
  String? _frame;
  List<String> _tileFrames = [];
  String _message = 'انقل الملفات بالكاميرا فقط، دون شبكة أو مسح متبادل.';
  double _progress = 0;

  bool get _active => _busy || _showInvite || _scanInvite ||
      _scanData || _sending || _finalizing;

  @override
  void initState() {
    super.initState();
    unawaited(_probeCapabilities());
    _manager.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((Object e) {
      if (mounted) setState(() => _message = 'فشل التهيئة: $e');
    });
  }

  Future<void> _probeCapabilities() async {
    if (mounted) setState(() => _probing = true);
    PhysicalCapabilities result;
    try {
      result = PhysicalCapabilities.fromMap(
        await NativeBridge.probePhysicalCapabilities(),
      );
    } catch (_) {
      result = const PhysicalCapabilities.unavailable();
    }
    if (!mounted) return;
    setState(() {
      _capabilities = result;
      final current = _profileId == null
          ? null : physicalProfileById(_profileId!);
      if (current == null || !result.availability(current).enabled) {
        _profileId = result.recommended(PhysicalMedium.qr)?.id;
      }
      _probing = false;
    });
  }

  PhysicalProfile? get _profile =>
      _profileId == null ? null : physicalProfileById(_profileId!);

  bool get _profileSupported =>
      _profile != null && _capabilities.availability(_profile!).enabled;

  @override
  void dispose() {
    _sendToken?.cancelled = true;
    unawaited(WakelockPlus.disable());
    _manager.dispose();
    _standardScanner.dispose();
    _streamScanner.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_active) return;
    try {
      final result = await FilePicker.platform.pickFiles(withData: false);
      if (result == null || result.files.isEmpty || !mounted) return;
      final path = result.files.single.path;
      if (path == null) throw const FileSystemException('مسار الملف غير متاح');
      setState(() {
        _selected = File(path);
        _message = 'الملف جاهز. اعرض رمز البداية للمستقبل.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'خطأ اختيار الملف: $error');
    }
  }

  Future<void> _beginSend() async {
    if (!_ready || _active || _selected == null || !_profileSupported) return;
    setState(() => _busy = true);
    try {
      await WakelockPlus.enable();
      if (!mounted) {
        await WakelockPlus.disable();
        return;
      }
      setState(() {
        _session = OneWaySession.create(profileId: _profileId!);
        _received = null;
        _showInvite = true;
        _message = 'امسح الرمز الثابت بالجهاز المستقبل، ثم اضغط بدء النقل.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر إنشاء الجلسة: $error');
      try { await WakelockPlus.disable(); } catch (_) {}
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _beginReceive() async {
    if (!_ready || _active || !_profileSupported) return;
    setState(() => _busy = true);
    try {
      await WakelockPlus.enable();
      if (!mounted) {
        await WakelockPlus.disable();
        return;
      }
      setState(() {
        _session = null;
        _received = null;
        _progress = 0;
        _scanInvite = true;
        _message = 'وجّه الكاميرا إلى رمز QR الثابت على جهاز المرسل.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر بدء الاستقبال: $error');
      try { await WakelockPlus.disable(); } catch (_) {}
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _transmit() async {
    final session = _session;
    final file = _selected;
    if (!_showInvite || session == null || file == null || _sending) return;
    final token = CancelToken();
    _sendToken = token;
    setState(() {
      _showInvite = false;
      _sending = true;
      _progress = 0;
      _frame = null;
      _message = 'جارٍ تجهيز الملف. ابقِ كاميرا المستقبل باتجاه الشاشة.';
    });
    File? encrypted;
    try {
      _manager.begin();
      encrypted = await _manager.prepare(file, session.passphrase);
      token.check();
      if (await encrypted.length() > 512 * 1024) {
        throw const FormatException('الملف أكبر من 512KB بعد التشفير.');
      }
      for (var left = 3; left > 0; left--) {
        token.check();
        if (mounted) setState(() => _countdown = left);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      token.check();
      if (mounted) setState(() {
        _countdown = 0;
        _message = 'بث QR جارٍ؛ أوقفه بعد اكتمال استقبال الملف.';
      });
      _manager.update(Phase.transferring);
      final engine = PhysicalEngine(
        Channel.qr,
        sessionId: session.sessionId,
        emitBatch: (packets) async {
          if (!token.cancelled && mounted) {
            setState(() {
              _tileFrames = packets.map(encodeQrFrame).toList();
              _frame = _tileFrames.first;
            });
          }
        },
        emit: (Uint8List packet) async {
          if (!token.cancelled && mounted) {
            setState(() => _frame = encodeQrFrame(packet));
          }
        },
      )..fps = physicalProfileById(session.profileId)!.qrFps
       ..qrTiles = physicalProfileById(session.profileId)!.qrTiles
       ..blockLength = physicalProfileById(session.profileId)!.qrBlockBytes;
      await engine.send(encrypted, null, token, (_, __) {});
    } on TransferCancelled {
      if (mounted) setState(() => _message = 'تم إيقاف البث.');
    } catch (error) {
      if (mounted) setState(() => _message = 'فشل النقل البصري: $error');
    } finally {
      if (encrypted != null && await encrypted.exists()) {
        await encrypted.delete();
      }
      try { await WakelockPlus.disable(); } catch (_) {}
      if (mounted) setState(() {
        _frame = null;
        _countdown = 0;
        _sending = false;
      });
    }
  }

  Future<void> _scan(BarcodeCapture capture) async {
    if (_scanBusy || _finalizing || !mounted) return;
    _scanBusy = true;
    try {
      final values = capture.barcodes.map((b) => b.rawValue)
          .whereType<String>();
      if (_scanInvite) {
        for (final value in values) {
          final session = OneWaySession.parse(value);
          if (session == null || !mounted || !_scanInvite) continue;
          final receivedProfile = physicalProfileById(session.profileId);
          if (receivedProfile?.medium != PhysicalMedium.qr ||
              session.profileId != _profileId || !_profileSupported) {
            if (mounted) setState(() => _message =
                'الوضع على المرسل: ${receivedProfile?.title ?? session.profileId}. '
                'اختر الوضع نفسه من القائمة على هذا الهاتف ثم امسح مرة أخرى.');
            return;
          }
          _manager.begin();
          _manager.update(Phase.waiting);
          _decoder = PhysicalDecoder(
            600 * 1024, expectedSessionId: session.sessionId,
          );
          setState(() {
            _session = session;
            _scanInvite = false;
            _scanData = true;
            _progress = 0;
            _message = 'وصلت رسالة البدء. انتظر الرموز المتحركة على نفس الشاشة.';
          });
          return;
        }
      } else if (_scanData) {
        final result = decodeQrCapture(_decoder, values);
        if (result == null) {
          final progress = _decoder.progress;
          if (mounted && (progress - _progress).abs() >= 0.01) {
            setState(() => _progress = progress);
          }
          return;
        }
        _finalizing = true;
        if (mounted) setState(() {
          _scanData = false;
          _progress = 1;
          _message = 'اكتمل الاستقبال. جارٍ التحقق من الملف...';
        });
        await _finishReceive(result);
      }
    } catch (error) {
      if (_decoder.header == null && _scanData) {
        if (mounted) setState(() {
          _progress = 0;
          _message = 'تجاهلنا إطارات غير صالحة. ما زلنا نستقبل.';
        });
      } else if (mounted) {
        setState(() => _message = 'خطأ أثناء المسح: $error');
      }
    } finally {
      _scanBusy = false;
    }
  }

  Future<void> _finishReceive(Uint8List payload) async {
    final password = _session?.passphrase;
    File? encrypted;
    try {
      if (password == null) throw StateError('لم تصل رسالة البدء');
      encrypted = File('${_manager.work.path}/qr-${DateTime.now().microsecondsSinceEpoch}.vdp');
      await encrypted.writeAsBytes(payload, flush: true);
      final received = await _manager.accept(encrypted, password, Channel.qr);
      if (mounted) setState(() {
        _received = received;
        _message = 'تم استلام الملف والتحقق من سلامته. '
            'سرعة حمولة الاستقبال: ${_decoder.payloadKiBPerSecond.toStringAsFixed(1)} KiB/s، '
            'إطارات سليمة: ${_decoder.validFrames}، '
            'إطارات مرفوضة: ${_decoder.rejectedFrames}.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'فشل التحقق: $error');
    } finally {
      if (encrypted != null && await encrypted.exists()) await encrypted.delete();
      try { await WakelockPlus.disable(); } catch (_) {}
      if (mounted) setState(() => _finalizing = false);
    }
  }

  void _stop() {
    _sendToken?.cancelled = true;
    if (_sending) {
      setState(() => _message = 'جارٍ إيقاف بث الرموز...');
      return;
    }
    setState(() {
      _showInvite = false;
      _scanInvite = false;
      _scanData = false;
      _message = 'تم إيقاف الجلسة. يمكنك البدء من جديد.';
    });
    unawaited(WakelockPlus.disable());
  }

  Widget _staticQr(String data) => Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.all(12),
    color: Colors.white,
    child: QrImageView(data: data, version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M, size: 306),
  );

  Widget _dataQr(String data, {bool tile = false}) {
    final version = _session == null ? 13 :
        (physicalProfileById(_session!.profileId)?.qrVersion ?? 13);
    final qr = QrCode(version, QrErrorCorrectLevel.L)
      ..addAlphaNumeric(data);
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      color: Colors.white,
      child: RepaintBoundary(
        child: QrImageView.withQr(
          qr: qr,
          size: tile ? double.infinity : version == 40
              ? MediaQuery.sizeOf(context).width - 48
              : 324,
        ),
      ),
    );
  }

  Widget _scanner() {
    final isStreaming = (_profile?.qrFps ?? 0) >= 9;
    return SizedBox(
      height: isStreaming ? MediaQuery.sizeOf(context).width - 32 : 320,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: MobileScanner(
          controller: isStreaming ? _streamScanner : _standardScanner,
          onDetect: _scan,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ViaDrop • الكاميرا')),
    body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('QR باتجاه واحد: امسح رمز البداية مرة واحدة ثم استقبل.',
          style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, children: [
          ChoiceChip(label: const Text('إرسال'), selected: _sendMode,
            onSelected: _active ? null : (_) => setState(() => _sendMode = true)),
          ChoiceChip(label: const Text('استقبال'), selected: !_sendMode,
            onSelected: _active ? null : (_) => setState(() => _sendMode = false)),
        ]),
        const SizedBox(height: 12),
        PhysicalProfileSelector(
          medium: PhysicalMedium.qr,
          capabilities: _capabilities,
          selectedId: _profileId,
          enabled: !_sending && !_busy && !_showInvite && !_scanData && !_finalizing,
          checking: _probing,
          onRefresh: () => unawaited(_probeCapabilities()),
          onChanged: (id) => setState(() {
            _profileId = id;
            _message = 'اختر التقنية نفسها على الجهاز الثاني قبل بدء النقل.';
          }),
        ),
        const SizedBox(height: 12),
        if (_sendMode) ...[
          OutlinedButton.icon(
            onPressed: _active ? null : _pick,
            icon: const Icon(Icons.attach_file),
            label: Text(_selected?.uri.pathSegments.last ?? 'اختر الملف'),
          ),
           if (!_active)
            FilledButton.icon(
              onPressed: _ready && _selected != null && _profileSupported ? _beginSend : null,
              icon: const Icon(Icons.qr_code),
              label: const Text('عرض QR البداية'),
            ),
          if (_showInvite) ...[
            const Text('امسح هذا الرمز بالمستقبل. يبقى ثابتاً حتى تبدأ البث.'),
            _staticQr(_session!.announcement),
            FilledButton.icon(
              onPressed: _transmit,
              icon: const Icon(Icons.play_arrow),
              label: const Text('بدء النقل • عد تنازلي ٣ ثوانٍ'),
            ),
          ],
          if (_sending) ...[
            if (_countdown > 0)
              Center(child: Text('$_countdown',
                style: const TextStyle(fontSize: 70, fontWeight: FontWeight.bold)))
            else if (_frame == null)
              const Center(child: CircularProgressIndicator())
            else
              if ((physicalProfileById(_session!.profileId)?.qrTiles ?? 1) == 4)
                AspectRatio(aspectRatio: 1, child: GridView.count(
                  crossAxisCount: 2, physics: const NeverScrollableScrollPhysics(),
                  children: _tileFrames.map((data) => _dataQr(data, tile: true)).toList(),
                ))
              else
                _dataQr(_frame!),
            const LinearProgressIndicator(),
          ],
        ] else ...[
          if (!_active)
            FilledButton.icon(
              onPressed: _ready && _profileSupported ? _beginReceive : null,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('استقبال بالـQR'),
            ),
          if (_scanInvite) ...[
            const Text('امسح رمز البداية الثابت على الهاتف المرسل.'),
            _scanner(),
          ],
          if (_scanData) ...[
            const Text('تم مسح البداية. وجّه الكاميرا إلى رموز البيانات.'),
            _scanner(),
            LinearProgressIndicator(value: _progress),
          ],
          if (_finalizing) const LinearProgressIndicator(),
          if (_received != null)
            FilledButton.tonalIcon(
              onPressed: () => OpenFilex.open(_received!.path),
              icon: const Icon(Icons.open_in_new),
              label: const Text('فتح الملف المستلم'),
            ),
        ],
        if (_active) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _finalizing ? null : _stop,
            icon: const Icon(Icons.stop),
            label: const Text('إيقاف العملية'),
          ),
        ],
        const SizedBox(height: 16),
        Card(child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(_message),
        )),
        const SizedBox(height: 8),
        const Text(
          'يُرسل مفتاح الجلسة داخل QR الافتتاحي، لذلك يستطيع أي شخص '
          'يمسح الرمز قراءة الملف المنقول. النقل باتجاه واحد ولا يتطلب '
          'مسح تأكيد أو شبكة.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    )),
  );
}
