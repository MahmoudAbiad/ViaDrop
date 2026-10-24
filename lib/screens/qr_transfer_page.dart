import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:open_filex/open_filex.dart';

import '../core/manager.dart';
import '../core/transfer.dart';
import '../engines/physical.dart';

/// Actual offline optical transport. No radio or URL is used as a data channel.
/// A shared passphrase must be exchanged privately outside the QR stream.
class QrTransferPage extends StatefulWidget {
  const QrTransferPage({super.key});

  @override
  State<QrTransferPage> createState() => _QrTransferPageState();
}

class _QrTransferPageState extends State<QrTransferPage> {
  final _manager = TransferManager();
  final _pass = TextEditingController();
  final _decoder = PhysicalDecoder(600 * 1024);
  File? _selected;
  File? _received;
  CancelToken? _token;
  bool _ready = false;
  bool _busy = false;
  bool _sending = false;
  bool _receiving = false;
  bool _finalizing = false;
  bool _sendMode = true;
  String? _frame;
  String _message = 'QR ينقل بيانات الملف نفسها من الشاشة إلى الكاميرا.';
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _manager.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((Object e) {
      if (mounted) setState(() => _message = 'فشل التهيئة: $e');
    });
  }

  @override
  void dispose() {
    _token?.cancelled = true;
    _pass.dispose();
    _manager.dispose();
    super.dispose();
  }

  bool get _validPass => _pass.text.length >= 12;

  Future<void> _pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: false);
      if (!mounted || result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) throw const FileSystemException('لم يتم توفير مسار الملف');
      setState(() {
        _selected = File(path);
        _message = 'اختر بدء البث ثم افتح الكاميرا على جهاز آخر.';
      });
    } catch (e) {
      if (mounted) setState(() => _message = 'اختيار الملف: $e');
    }
  }

  Future<void> _startSending() async {
    if (!_ready || _busy || _selected == null || !_validPass) {
      setState(() => _message = 'اختر ملفاً وعبارة مرور من 12 حرفاً على الأقل.');
      return;
    }
    final token = CancelToken();
    _token = token;
    setState(() {
      _busy = true;
      _sending = false;
      _frame = null;
      _message = 'يُجهّز الملف المشفّر...';
    });
    try {
      _manager.begin();
      final sealed = await _manager.prepare(_selected!, _pass.text);
      if (token.cancelled) return;
      final length = await sealed.length();
      if (length > 512 * 1024) {
        throw const FormatException('النقل البصري الحالي مخصص للملفات الصغيرة حتى 512KB تقريباً بعد التشفير.');
      }
      _manager.update(Phase.transferring);
      setState(() {
        _sending = true;
        _message = 'وجّه كاميرا الجهاز المستقبل للشاشة. البث يتكرر حتى تضغط إيقاف.';
      });
      final engine = PhysicalEngine(
        Channel.qr,
        emit: (Uint8List packet) async {
          if (!token.cancelled && mounted) {
            setState(() => _frame = 'VDQR:' + base64UrlEncode(packet));
          }
        },
      )..fps = 3
       ..blockLength = 180;
      await engine.send(sealed, null, token, (_, __) {});
    } on TransferCancelled {
      // Stopping transmission is an expected user action.
    } catch (e) {
      if (mounted) setState(() => _message = 'تعذّر بدء البث: $e');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _busy = false;
          _frame = null;
        });
      }
    }
  }

  void _stopSending() {
    _token?.cancelled = true;
    setState(() {
      _sending = false;
      _frame = null;
      _message = 'توقف البث. هذا لا يؤكد أن المستقبل أنهى الاستقبال.';
    });
  }

  void _startReceiving() {
    if (!_ready || !_validPass) {
      setState(() => _message = 'اكتب نفس عبارة المرور المستخدمة لدى المرسل (12 حرفاً على الأقل).');
      return;
    }
    _manager.begin();
    _manager.update(Phase.waiting);
    setState(() {
      _receiving = true;
      _finalizing = false;
      _progress = 0;
      _received = null;
      _message = 'وجّه الكاميرا نحو رموز QR المتحركة على الجهاز المرسل.';
    });
  }

  Future<void> _scan(BarcodeCapture capture) async {
    if (!_receiving || _finalizing) return;
    for (final barcode in capture.barcodes) {
      final text = barcode.rawValue;
      if (text == null || !text.startsWith('VDQR:')) continue;
      Uint8List bytes;
      try {
        bytes = base64Url.decode(text.substring(5));
      } catch (_) {
        continue;
      }
      try {
        final complete = _decoder.add(bytes);
        if (complete == null) {
          final progress = _decoder.progress;
          if ((progress - _progress).abs() >= 0.01 && mounted) {
            setState(() => _progress = progress);
          }
          return;
        }
        _finalizing = true;
        setState(() {
          _receiving = false;
          _progress = 1;
          _message = 'اكتملت الإطارات، جارٍ فك التشفير والتحقق...';
        });
        final encrypted = File(
          _manager.work.path + '/qr-' + DateTime.now().microsecondsSinceEpoch.toString() + '.vdp',
        );
        await encrypted.writeAsBytes(complete, flush: true);
        try {
          final result = await _manager.accept(encrypted, _pass.text, Channel.qr);
          if (mounted) {
            setState(() {
              _received = result;
              _message = 'تم استلام الملف والتحقق منه بنجاح.';
            });
          }
        } finally {
          if (await encrypted.exists()) await encrypted.delete();
        }
        return;
      } catch (e) {
        if (mounted) {
          setState(() {
            _receiving = false;
            _message = 'فشل التحقق من الاستقبال: $e';
          });
        }
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _sending || _receiving || _busy;
    return Scaffold(
      appBar: AppBar(title: const Text('ViaDrop • Camera / QR')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('نقل بصري مستقل تماماً: شاشة ← كاميرا. لا شبكة ولا بلوتوث.',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, children: [
            ChoiceChip(label: const Text('إرسال'), selected: _sendMode,
              onSelected: active ? null : (_) => setState(() => _sendMode = true)),
            ChoiceChip(label: const Text('استقبال'), selected: !_sendMode,
              onSelected: active ? null : (_) => setState(() => _sendMode = false)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            enabled: !active,
            decoration: const InputDecoration(
              labelText: 'عبارة المرور المشتركة (12 حرفاً على الأقل)',
              border: OutlineInputBorder(),
              helperText: 'لا تُرسل كلمة المرور داخل رموز QR.',
            ),
          ),
          const SizedBox(height: 16),
          if (_sendMode) ...[
            OutlinedButton.icon(onPressed: active ? null : _pick,
              icon: const Icon(Icons.attach_file),
              label: Text(_selected?.uri.pathSegments.last ?? 'اختر ملفاً صغيراً')),
            const SizedBox(height: 10),
            if (!_sending)
              FilledButton.icon(onPressed: _ready && !_busy ? _startSending : null,
                icon: const Icon(Icons.qr_code), label: const Text('ابدأ بث QR')),
            if (_sending) ...[
              Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.all(10),
                color: Colors.white,
                child: _frame == null
                    ? const CircularProgressIndicator()
                    : QrImageView(data: _frame!, version: QrVersions.auto,
                        errorCorrectionLevel: QrErrorCorrectLevel.L, size: 290),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(onPressed: _stopSending,
                icon: const Icon(Icons.stop), label: const Text('إيقاف البث')),
            ],
          ] else ...[
            if (!_receiving && !_finalizing)
              FilledButton.icon(onPressed: _ready ? _startReceiving : null,
                icon: const Icon(Icons.camera_alt_outlined), label: const Text('ابدأ مسح QR')),
            if (_receiving)
              SizedBox(height: 310, child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(onDetect: _scan),
              )),
            if (_receiving)
              TextButton(onPressed: () => setState(() => _receiving = false),
                child: const Text('إيقاف المسح')),
            if (_receiving || _finalizing)
              LinearProgressIndicator(value: _progress),
            if (_received != null)
              FilledButton.tonalIcon(
                onPressed: () => OpenFilex.open(_received!.path),
                icon: const Icon(Icons.open_in_new), label: const Text('افتح الملف المستلم')),
          ],
          const SizedBox(height: 16),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(_message),
          )),
          const SizedBox(height: 8),
          const Text('تجريبي: يحتاج اختباراً بين هاتفين. سرعة الالتقاط تعتمد على الكاميرا والإضاءة.',
            style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
