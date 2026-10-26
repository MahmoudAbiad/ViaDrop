import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:open_filex/open_filex.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/manager.dart';
import '../core/one_way_session.dart';
import '../core/physical_profiles.dart';
import '../engines/native.dart';
import '../engines/color_optical.dart';
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

class _QrTransferPageState extends State<QrTransferPage> with WidgetsBindingObserver {
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
  StreamSubscription<dynamic>? _colorEvents;
  Future<void>? _colorStopping;
  int? _colorTexture, _colorGeneration;
  int _colorWidth = 1024, _colorHeight = 1024, _colorRotation = 0;
  String _colorMatrix = 'bt601';
  bool get _isColor => _profile?.color ?? false;
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
    WidgetsBinding.instance.addObserver(this);
    _colorEvents = ColorOptical.events.listen(_onColorEvent, onError: (Object error) {
      if (mounted && _isColor && _active) {
        _stop();
        setState(() => _message = 'تعذر استقبال أحداث الألوان: $error');
      }
    });
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
      if (current == null || !result.availability(current, sending: _sendMode).enabled) {
        _profileId = result.recommended(PhysicalMedium.qr, sending: _sendMode)?.id;
      }
      _probing = false;
    });
  }

  PhysicalProfile? get _profile =>
      _profileId == null ? null : physicalProfileById(_profileId!);

  bool get _profileSupported =>
      _profile != null && _capabilities.availability(_profile!, sending: _sendMode).enabled;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_colorEvents?.cancel());
    unawaited(_stopColor());
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
      await _stopColor();
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
      await _stopColor();
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
      if (physicalProfileById(session.profileId)!.color) {
        final display = await ColorOptical.startSender();
        token.check();
        if (!mounted) throw TransferCancelled();
        setState(() {
          _colorTexture = display['textureId'] as int;
          _colorGeneration = display['generation'] as int;
        });
        await WidgetsBinding.instance.endOfFrame;
      }
      for (var left = 3; left > 0; left--) {
        token.check();
        if (mounted) setState(() => _countdown = left);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      token.check();
      if (mounted) setState(() {
        _countdown = 0;
        _message = 'البث البصري جارٍ؛ أوقفه بعد اكتمال استقبال الملف.';
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
          token.check();
          if (physicalProfileById(session.profileId)!.color) {
            await ColorOptical.present(packet);
            token.check();
          } else if (mounted) {
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
      await _stopColor();
      if (mounted) setState(() { _colorTexture = null; _colorGeneration = null; });
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
          if (physicalProfileById(session.profileId)?.color ?? false) {
            await ((_profile?.qrFps ?? 0) >= 9 ? _streamScanner : _standardScanner).stop();
            if (!mounted || !_scanInvite) return;
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
          if (physicalProfileById(session.profileId)?.color ?? false) {
            await WidgetsBinding.instance.endOfFrame;
            await _startColorReceiver(session);
          }
          return;
        }
      } else if (_scanData && !_isColor) {
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
    unawaited(_stopColor());
    if (_sending) {
      setState(() => _message = 'جارٍ إيقاف بث الرموز...');
      return;
    }
    setState(() {
      _colorTexture = null;
      _colorGeneration = null;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.detached) &&
        mounted && _isColor && _active) _stop();
  }

  Future<void> _stopColor() => _colorStopping ??= ColorOptical.stop()
      .catchError((Object _) {})
      .whenComplete(() => _colorStopping = null);

  Future<void> _startColorReceiver(OneWaySession session) async {
    try {
      if (!await Permission.camera.request().isGranted) {
        throw StateError('لم تُمنح صلاحية الكاميرا');
      }
      if (!mounted || !_scanData || _session != session) return;
      final camera = await ColorOptical.startReceiver(_colorMatrix);
      if (!mounted || !_scanData || _session != session) {
        await _stopColor(); return;
      }
      setState(() {
        _colorTexture = camera['textureId'] as int;
        _colorGeneration = camera['generation'] as int;
        _colorWidth = camera['width'] as int;
        _colorHeight = camera['height'] as int;
        _colorRotation = camera['rotation'] as int;
        _message = 'وجّه الكاميرا إلى كامل إطار الألوان. أبقِ الهاتف ثابتاً؛ التقدم يحسب من البيانات المفكوكة فعلياً.';
      });
    } catch (error) {
      if (!mounted || _session != session || !_scanData) return;
      await _stopColor();
      if (mounted && _session == session) setState(() {
        _scanData = false; _colorTexture = null; _colorGeneration = null;
        _message = 'تعذر بدء كاميرا الألوان: $error';
      });
      unawaited(WakelockPlus.disable());
    }
  }

  void _onColorEvent(dynamic event) {
    if (!mounted || !_scanData || !_isColor || _finalizing || event is! Map ||
        event['generation'] != _colorGeneration) return;
    if (event['type'] == 'error') {
      _stop();
      setState(() => _message = 'خطأ نقل الألوان: ${event['message']}');
      return;
    }
    final packet = event['data'];
    if (event['type'] != 'packet' || packet is! Uint8List) return;
    try {
      final result = _decoder.add(packet);
      if (result == null) {
        final progress = _decoder.progress;
        if ((progress - _progress).abs() >= 0.01) setState(() => _progress = progress);
        return;
      }
      _finalizing = true;
      setState(() {
        _scanData = false; _colorTexture = null; _colorGeneration = null;
        _progress = 1; _message = 'اكتملت بيانات الألوان. جارٍ التحقق من الملف...';
      });
      unawaited(_completeColorReceive(result));
    } catch (error) {
      setState(() => _message = 'تعذر إعادة بناء الإطار: $error. ما زلنا نستقبل.');
    }
  }

  Future<void> _completeColorReceive(Uint8List result) async {
    await _stopColor();
    if (mounted) await _finishReceive(result);
  }

  Widget _colorPreview() {
    if (_colorTexture == null) return const SizedBox(height: 320,
      child: Center(child: CircularProgressIndicator()));
    final odd = _colorRotation % 180 != 0;
    return AspectRatio(
      aspectRatio: odd ? _colorHeight / _colorWidth : _colorWidth / _colorHeight,
      child: RotatedBox(quarterTurns: _colorRotation ~/ 90,
        child: Texture(textureId: _colorTexture!, filterQuality: FilterQuality.none)),
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
  Widget build(BuildContext context) {
    if (_sending && _isColor && _colorTexture != null) {
      return Scaffold(backgroundColor: Colors.white,
        body: SafeArea(child: Column(children: [
          if (_countdown > 0) Text('$_countdown',
            style: const TextStyle(fontSize: 52, color: Colors.black)),
          Expanded(child: Center(child: AspectRatio(aspectRatio: 1,
            child: Texture(textureId: _colorTexture!, filterQuality: FilterQuality.none)))),
          Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            Text(_message, style: const TextStyle(color: Colors.black)),
            OutlinedButton.icon(onPressed: _stop, icon: const Icon(Icons.stop),
              label: const Text('إيقاف بث الألوان')),
          ])),
        ])),
      );
    }
    return Scaffold(
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
          sending: _sendMode,
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
        if (_isColor && !_sendMode) ...[
          DropdownButtonFormField<String>(
            value: _colorMatrix,
            decoration: const InputDecoration(labelText: 'معايرة لون الكاميرا • اختيار صريح'),
            items: const [
              DropdownMenuItem(value: 'bt601', child: Text('BT.601 limited • جرّبه أولاً')),
              DropdownMenuItem(value: 'bt709', child: Text('BT.709 limited • معايرة بديلة')),
            ],
            onChanged: _active ? null : (value) => setState(() => _colorMatrix = value!),
          ),
          const Text('اختيار تجريبي يدوي؛ لا يثبت فضاء لون الكاميرا. إن لم يتحرك التقدم، أوقف الجلسة وجرّب المعايرة الأخرى.'),
          const SizedBox(height: 12),
        ],
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
            if (_isColor) _colorPreview() else _scanner(),
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
}
