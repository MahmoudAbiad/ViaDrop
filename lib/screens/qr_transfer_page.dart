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
import '../core/qr_pairing.dart';
import '../core/transfer.dart';
import '../engines/physical.dart';
import '../engines/qr_codec.dart';

/// Independent optical data transport: two QR scans pair devices using
/// ephemeral X25519 keys. Actual file bytes are sent through animated QRs.
class QrTransferPage extends StatefulWidget {
  const QrTransferPage({super.key});

  @override
  State<QrTransferPage> createState() => _QrTransferPageState();
}

class _QrTransferPageState extends State<QrTransferPage> {
  final _manager = TransferManager();
  OpticalPairing? _pairing;
  PhysicalDecoder _decoder = PhysicalDecoder(600 * 1024);
  File? _selected;
  File? _received;
  CancelToken? _sendToken;
  bool _ready = false;
  bool _busy = false;
  bool _sendMode = true;
  bool _showInvite = false;
  bool _scanReply = false;
  bool _scanInvite = false;
  bool _showReply = false;
  bool _scanData = false;
  bool _sending = false;
  bool _finalizing = false;
  bool _fastMode = false;
  bool _scanBusy = false;
  String? _frame;
  String _message = 'الإرسال عبر الشاشة والكاميرا بدون إنترنت أو كلمة مرور.';
  double _progress = 0;

  bool get _active => _busy || _showInvite || _scanReply || _scanInvite ||
      _showReply || _scanData || _sending || _finalizing;

  @override
  void initState() {
    super.initState();
    _manager.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((Object error) {
      if (mounted) setState(() => _message = 'فشل التهيئة: $error');
    });
  }

  @override
  void dispose() {
    _sendToken?.cancelled = true;
    unawaited(WakelockPlus.disable());
    _manager.dispose();
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
        _message = 'اضغط إنشاء اقتران وأرِ الرمز للهاتف المستقبل.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'خطأ اختيار الملف: $error');
    }
  }

  Future<void> _beginInvite() async {
    if (!_ready || _active || _selected == null) {
      setState(() => _message = 'اختر ملفاً أولاً.');
      return;
    }
    setState(() => _busy = true);
    try {
      await WakelockPlus.enable();
      final pairing = await OpticalPairing.createSender();
      if (!mounted) {
        await WakelockPlus.disable();
        return;
      }
      setState(() {
        _pairing = pairing;
        _showInvite = true;
        _message = '1/2: دع الهاتف الآخر يمسح رمز الاقتران الثابت.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'فشل إنشاء الاقتران: $error');
      try { await WakelockPlus.disable(); } catch (_) {}
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _beginReceive() async {
    if (!_ready || _active) return;
    setState(() => _busy = true);
    try {
      await WakelockPlus.enable();
      if (!mounted) {
        await WakelockPlus.disable();
        return;
      }
      setState(() {
        _pairing = null;
        _received = null;
        _scanInvite = true;
        _message = '1/2: امسح رمز الاقتران المعروض على المرسل.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر فتح الاقتران: $error');
      try { await WakelockPlus.disable(); } catch (_) {}
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _beginReplyScan() {
    if (_pairing == null || !_showInvite) return;
    setState(() {
      _showInvite = false;
      _scanReply = true;
      _message = '2/2: امسح الآن رمز التأكيد الظاهر على الجهاز المستقبل.';
    });
  }

  void _beginDataScan() {
    final pair = _pairing;
    if (pair == null || pair.passphrase == null || !_showReply) return;
    _manager.begin();
    _manager.update(Phase.waiting);
    _decoder = PhysicalDecoder(
      600 * 1024, expectedSessionId: pair.sessionId,
    );
    setState(() {
      _showReply = false;
      _scanData = true;
      _progress = 0;
      _message = 'الاقتران جاهز. وجّه الكاميرا إلى رموز الملف المتحركة.';
    });
  }

  Future<void> _transmit() async {
    final pair = _pairing;
    final file = _selected;
    final password = pair?.passphrase;
    if (pair == null || password == null || file == null || _sending) return;
    final token = CancelToken();
    _sendToken = token;
    setState(() {
      _sending = true;
      _busy = true;
      _progress = 0;
      _message = 'اكتمل الاقتران. جارٍ تجهيز ملف مشفّر تلقائياً...';
    });
    File? encrypted;
    try {
      _manager.begin();
      encrypted = await _manager.prepare(file, password);
      if (token.cancelled) return;
      if (await encrypted.length() > 512 * 1024) {
        throw const FormatException(
          'الملف أكبر من الحد الحالي للنقل بالكاميرا (512KB بعد التشفير).',
        );
      }
      _manager.update(Phase.transferring);
      if (mounted) {
        setState(() => _message =
          'أصبح الإرسال نشطاً. افتح مسح الملف في الهاتف المستقبل.');
      }
      final engine = PhysicalEngine(
        Channel.qr,
        sessionId: pair.sessionId,
        emit: (Uint8List packet) async {
          if (!token.cancelled && mounted) {
            setState(() => _frame = encodeQrFrame(packet));
          }
        },
      )
        ..fps = _fastMode ? 7 : 5
        ..blockLength = _fastMode ? 320 : 280;
      await engine.send(encrypted, null, token, (_, __) {});
    } on TransferCancelled {
      // User stopped the repeating QR broadcast.
    } catch (error) {
      if (mounted) setState(() => _message = 'فشل النقل البصري: $error');
    } finally {
      if (encrypted != null && await encrypted.exists()) {
        await encrypted.delete();
      }
      try { await WakelockPlus.disable(); } catch (_) {}
      if (mounted) setState(() {
        _frame = null;
        _sending = false;
        _busy = false;
      });
    }
  }

  Future<void> _scan(BarcodeCapture capture) async {
    if (_scanBusy || _finalizing || !mounted) return;
    _scanBusy = true;
    try {
      final values = capture.barcodes.map((b) => b.rawValue).whereType<String>();
      if (_scanInvite) {
        for (final value in values) {
          if (!value.startsWith(OpticalPairing.invitePrefix)) continue;
          final pair = await OpticalPairing.acceptInvitation(value);
          if (pair != null && mounted && _scanInvite) {
            setState(() {
              _pairing = pair;
              _scanInvite = false;
              _showReply = true;
              _message = 'تم مسح الاقتران. أعرض هذا الرمز للمرسل كي يؤكد الاتصال.';
            });
            return;
          }
        }
      } else if (_scanReply) {
        final pair = _pairing;
        if (pair == null) return;
        for (final value in values) {
          if (!value.startsWith(OpticalPairing.replyPrefix)) continue;
          if (await pair.acceptReply(value) && mounted && _scanReply) {
            setState(() => _scanReply = false);
            unawaited(_transmit());
            return;
          }
        }
      } else if (_scanData) {
        final complete = decodeQrCapture(_decoder, values);
        if (complete == null) {
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
          _message = 'اكتمل الاستقبال، جارٍ فك التشفير والتحقق...';
        });
        await _finishReceive(complete);
      }
    } catch (error) {
      if (_decoder.header == null && _scanData) {
        if (mounted) setState(() {
          _progress = 0;
          _message = 'إطارات غير صالحة؛ ما زلنا نستقبل الإرسال المقترن.';
        });
      } else {
        if (mounted) setState(() => _message = 'خطأ أثناء المسح: $error');
      }
    } finally {
      _scanBusy = false;
    }
  }

  Future<void> _finishReceive(Uint8List payload) async {
    final pass = _pairing?.passphrase;
    File? encrypted;
    try {
      if (pass == null) throw StateError('اقتران غير صالح');
      encrypted = File(_manager.work.path + '/qr-' +
          DateTime.now().microsecondsSinceEpoch.toString() + '.vdp');
      await encrypted.writeAsBytes(payload, flush: true);
      final result = await _manager.accept(encrypted, pass, Channel.qr);
      if (mounted) setState(() {
        _received = result;
        _message = 'نجح الاستقبال وفك التشفير والتحقق من سلامة الملف.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'فشل التحقق من الملف: $error');
    } finally {
      if (encrypted != null && await encrypted.exists()) await encrypted.delete();
      try { await WakelockPlus.disable(); } catch (_) {}
      if (mounted) setState(() => _finalizing = false);
    }
  }

  void _stop() {
    _sendToken?.cancelled = true;
    setState(() {
      _showInvite = false;
      _scanReply = false;
      _scanInvite = false;
      _showReply = false;
      _scanData = false;
      _sending = false;
      _message = 'تم إيقاف الجلسة. يمكنك بدء اقتران جديد.';
    });
    unawaited(WakelockPlus.disable());
  }

  Widget _staticQr(String value) => Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.all(12),
    color: Colors.white,
    child: QrImageView(data: value, version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M, size: 306),
  );

  /// qr_flutter's default string constructor uses Byte mode. Explicitly
  /// choose Alphanumeric mode so Base45 actually lowers module density.
  Widget _dataQr(String value) {
    final qr = QrCode(13, QrErrorCorrectLevel.L)
      ..addAlphaNumeric(value);
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      color: Colors.white,
      child: QrImageView.withQr(qr: qr, size: 324),
    );
  }

  Widget _scanner() => SizedBox(
    height: 320,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: MobileScanner(onDetect: _scan),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ViaDrop • الكاميرا')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('النقل بالكاميرا فقط • اقتران بمسح QR دون كلمة مرور',
            style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, children: [
            ChoiceChip(label: const Text('إرسال'), selected: _sendMode,
              onSelected: _active ? null : (_) => setState(() => _sendMode = true)),
            ChoiceChip(label: const Text('استقبال'), selected: !_sendMode,
              onSelected: _active ? null : (_) => setState(() => _sendMode = false)),
          ]),
          const SizedBox(height: 12),
          if (_sendMode) ...[
            OutlinedButton.icon(
              onPressed: _active ? null : _pick,
              icon: const Icon(Icons.attach_file),
              label: Text(_selected?.uri.pathSegments.last ?? 'اختر الملف'),
            ),
            if (!_active)
              SwitchListTile(
                title: const Text('QR سريع (تجريبي)'),
                subtitle: const Text('أسرع لكن قد تخسر الكاميرات القديمة إطارات أكثر.'),
                value: _fastMode,
                onChanged: (value) => setState(() => _fastMode = value),
              ),
            const SizedBox(height: 10),
            if (!_active)
              FilledButton.icon(onPressed: _ready ? _beginInvite : null,
                icon: const Icon(Icons.qr_code), label: const Text('إنشاء اقتران')),
            if (_showInvite) ...[
              const Text('1. خلي الجهاز المستقبل يمسح هذا الرمز.'),
              _staticQr(_pairing!.invitation),
              FilledButton.icon(
                onPressed: _beginReplyScan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('مسح تأكيد الجهاز الثاني'),
              ),
            ],
            if (_scanReply) ...[
              const Text('2. امسح رمز التأكيد الظاهر في الهاتف المستقبل.'),
              _scanner(),
            ],
            if (_sending)
              _frame == null
                  ? const Center(child: CircularProgressIndicator())
                  : _dataQr(_frame!),
            if (_sending)
              LinearProgressIndicator(value: null),
          ] else ...[
            if (!_active)
              FilledButton.icon(
                onPressed: _ready ? _beginReceive : null,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('مسح اقتران المرسل'),
              ),
            if (_scanInvite) ...[
              const Text('1. امسح رمز الاقتران الثابت من شاشة المرسل.'),
              _scanner(),
            ],
            if (_showReply) ...[
              const Text('2. اعرض هذا الرمز للمرسل ليؤكد الاقتران.'),
              _staticQr(_pairing!.reply),
              FilledButton.icon(
                onPressed: _beginDataScan,
                icon: const Icon(Icons.camera_alt),
                label: const Text('تم التأكيد • ابدأ استقبال الملف'),
              ),
            ],
            if (_scanData) ...[
              const Text('وجّه الكاميرا إلى إطارات QR المتحركة.'),
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
            'يبدأ بث الملف بعد أن يمسح المرسل رمز التأكيد من المستقبل. '
            'المفتاح يُشتق تلقائياً ولا يظهر على الشاشة. '
            'السرعة الفعلية تعتمد على وضوح الشاشة والكاميرا.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      )),
    );
  }
}
