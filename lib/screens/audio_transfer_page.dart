import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/manager.dart';
import '../core/transfer.dart';
import '../engines/native.dart';
import '../engines/physical.dart';

/// Speaker-to-microphone data transport. No LAN, mobile network, or Bluetooth
/// is used for payload delivery. Requires real Android device verification.
class AudioTransferPage extends StatefulWidget {
  const AudioTransferPage({super.key});

  @override
  State<AudioTransferPage> createState() => _AudioTransferPageState();
}

class _AudioTransferPageState extends State<AudioTransferPage> {
  final _manager = TransferManager();
  final _pass = TextEditingController();
  final _text = TextEditingController();
  StreamSubscription<dynamic>? _events;
  File? _source;
  File? _result;
  PhysicalDecoder _decoder = PhysicalDecoder(4096);
  CancelToken? _sendToken;
  bool _ready = false;
  bool _receiving = false;
  bool _sending = false;
  bool _finalizing = false;
  bool _highFrequency = false;
  bool _sendMode = true;
  double _progress = 0;
  String _status = 'نقل صوتي حقيقي من السماعة إلى الميكروفون دون أي شبكة.';

  @override
  void initState() {
    super.initState();
    _manager.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((Object e) {
      _show('فشل التهيئة: ' + e.toString());
    });
  }

  void _show(String status) {
    if (mounted) setState(() => _status = status);
  }

  bool get _active => _receiving || _sending || _finalizing;
  bool get _validPass => _pass.text.length >= 12;

  Future<void> _pick() async {
    try {
      final files = await FilePicker.platform.pickFiles(withData: false);
      if (files == null || files.files.isEmpty || !mounted) return;
      final path = files.files.single.path;
      if (path == null) throw const FileSystemException('Missing file path');
      setState(() => _source = File(path));
    } catch (error) {
      _show('تعذر اختيار الملف: ' + error.toString());
    }
  }

  Future<File?> _inputFile() async {
    if (_text.text.trim().isNotEmpty) {
      final file = File(_manager.work.path + '/audio-note-' +
          DateTime.now().microsecondsSinceEpoch.toString() + '.txt');
      await file.writeAsString(_text.text);
      return file;
    }
    return _source;
  }

  Future<void> _startSend() async {
    if (!_ready || _active || !_validPass) {
      _show('أدخل عبارة مرور مشتركة من 12 حرفاً على الأقل.');
      return;
    }
    File? encrypted;
    var wakeLockActive = false;
    final token = CancelToken();
    _sendToken = token;
    setState(() {
      _sending = true;
      _progress = 0;
      _status = 'جار تجهيز البيانات المشفّرة...';
    });
    try {
      final input = await _inputFile();
      if (input == null) throw StateError('اختر ملفاً أو اكتب نصاً');
      // The acoustic channel is deliberately restricted to tiny envelopes.
      if (await input.length() > 2000) {
        throw StateError('الملف أكبر من حد الصوت التجريبي (2KB).');
      }
      _manager.begin();
      encrypted = await _manager.prepare(input, _pass.text);
      if (token.cancelled) return;
      if (await encrypted.length() > 4096) {
        throw StateError('حجم البيانات بعد التشفير أكبر من حد الصوت (4KB).');
      }
      await WakelockPlus.enable();
      wakeLockActive = true;
      _manager.update(Phase.transferring);
      _show('يُرسل الصوت الآن. احتفظ بالهاتفين قريبين ولا تخفض مستوى الصوت.');
      final engine = PhysicalEngine(
        Channel.audio,
        emit: (Uint8List packet) => NativeBridge.play(packet, _highFrequency),
        stopListening: NativeBridge.stopAudio,
      );
      await engine.send(encrypted, null, token, (sent, total) {
        if (mounted) setState(() => _progress = (sent / total).clamp(0, 1));
      });
    } on TransferCancelled {
      _show('أوقفتَ البث. لا يوجد تأكيد تلقائي بأن الهاتف الآخر أكمل الاستقبال.');
    } catch (error) {
      _show('فشل الإرسال الصوتي: ' + error.toString());
    } finally {
      if (wakeLockActive) {
        try { await WakelockPlus.disable(); } catch (_) {}
      }
      if (encrypted != null && await encrypted.exists()) {
        await encrypted.delete();
      }
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _stopSend() async {
    _sendToken?.cancelled = true;
    try {
      await NativeBridge.stopAudio();
    } catch (error) {
      _show('فشل إيقاف الصوت: ' + error.toString());
    }
  }

  Future<void> _startReceive() async {
    if (!_ready || _active || !_validPass) {
      _show('اكتب نفس عبارة المرور على الجهازين قبل الاستقبال.');
      return;
    }
    _decoder = PhysicalDecoder(4096);
    _manager.begin();
    _manager.update(Phase.waiting);
    _events = NativeBridge.events.listen(
      _handleEvent,
      onError: (Object error) => unawaited(_failReceive('خطأ في استقبال الصوت: $error')),
    );
    try {
      await WakelockPlus.enable();
      if (!mounted) {
        await _events?.cancel();
        _events = null;
        await WakelockPlus.disable();
        return;
      }
      // Mark the session active before native audio starts. Otherwise an
      // immediate decoder failure can arrive while _receiving is still false.
      setState(() {
        _receiving = true;
        _progress = 0;
        _result = null;
        _status = 'جارٍ تشغيل الميكروفون...';
      });
      await NativeBridge.listen();
      if (mounted && _receiving) {
        _show('يستمع الميكروفون الآن للإشارات الصوتية. قرّب الجهازين.');
      }
    } catch (error) {
      await _stopReceive();
      _show('تعذّر فتح الميكروفون: $error');
    }
  }

  void _handleEvent(dynamic data) {
    if (!_receiving || _finalizing || data is! Map) return;
    if (data['type'] == 'error') {
      unawaited(_failReceive('المودم الصوتي: ${data['message'] ?? 'خطأ'}'));
      return;
    }
    if (data['type'] != 'audioData') return;
    final raw = data['data'];
    if (raw is! List<int>) return;
    try {
      final complete = _decoder.add(Uint8List.fromList(raw));
      if (complete == null) {
        if (mounted) setState(() => _progress = _decoder.progress.clamp(0, 1));
        return;
      }
      _finalizing = true;
      unawaited(_finishReceive(complete));
    } catch (error) {
      if (_decoder.header == null) {
        // A completed burst with a bad payload checksum was rejected.
        // The decoder discarded the corrupted session, so reset the UI as
        // well while keeping the microphone ready for a fresh transmission.
        if (mounted) {
          setState(() {
            _progress = 0;
            _status = 'تم تجاهل إرسال صوتي تالف. ما زلنا نستمع لإرسال جديد.';
          });
        }
      } else {
        _show('إطار صوتي غير صالح: $error');
      }
    }
  }

  Future<void> _failReceive(String message) async {
    if (!_receiving) return;
    await _stopReceive();
    _show(message);
  }

  Future<void> _finishReceive(Uint8List encryptedData) async {
    File? temp;
    try {
      temp = File(_manager.work.path + '/audio-' +
          DateTime.now().microsecondsSinceEpoch.toString() + '.vdp');
      await temp.writeAsBytes(encryptedData, flush: true);
      final received = await _manager.accept(temp, _pass.text, Channel.audio);
      if (mounted) setState(() {
        _result = received;
        _progress = 1;
        _status = 'تم استلام الملف وفك التشفير والتحقق منه بنجاح.';
      });
    } catch (error) {
      _show('فشل فك التشفير أو فحص سلامة الملف: ' + error.toString());
    } finally {
      if (temp != null && await temp.exists()) await temp.delete();
      await _stopReceive();
      if (mounted) setState(() => _finalizing = false);
    }
  }

  Future<void> _stopReceive() async {
    try {
      await NativeBridge.stopAudio();
    } catch (_) {}
    await _events?.cancel();
    _events = null;
    try { await WakelockPlus.disable(); } catch (_) {}
    if (mounted) setState(() => _receiving = false);
  }

  @override
  void dispose() {
    _sendToken?.cancelled = true;
    _events?.cancel();
    NativeBridge.stopAudio();
    unawaited(WakelockPlus.disable());
    _pass.dispose();
    _text.dispose();
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ViaDrop • Audio')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('السماعة ← الميكروفون. لا حاجة لإنترنت أو Wi-Fi أو Bluetooth.'),
          const SizedBox(height: 12),
          Wrap(spacing: 12, children: [
            ChoiceChip(
              label: const Text('إرسال'),
              selected: _sendMode,
              onSelected: _active ? null : (_) => setState(() => _sendMode = true),
            ),
            ChoiceChip(
              label: const Text('استقبال'),
              selected: !_sendMode,
              onSelected: _active ? null : (_) => setState(() => _sendMode = false),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            enabled: !_active,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'عبارة المرور المشتركة (12 حرفاً على الأقل)',
            ),
          ),
          const SizedBox(height: 12),
          if (_sendMode) ...[
            TextField(
              controller: _text,
              enabled: !_active,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'اكتب نصاً قصيراً (له الأولوية على الملف المحدد)',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _active ? null : _pick,
              icon: const Icon(Icons.attach_file),
              label: Text(_source?.uri.pathSegments.last ?? 'أو اختر ملفاً صغيراً'),
            ),
            SwitchListTile(
              title: const Text('الترددات العالية (تجريبية)'),
              subtitle: const Text('قد لا تدعمها سماعة أو ميكروفون بعض الهواتف.'),
              value: _highFrequency,
              onChanged: _active ? null : (value) => setState(() => _highFrequency = value),
            ),
            if (!_sending)
              FilledButton.icon(
                onPressed: _ready && !_finalizing ? _startSend : null,
                icon: const Icon(Icons.volume_up),
                label: const Text('بدء بث البيانات صوتياً'),
              ),
            if (_sending)
              FilledButton.tonalIcon(
                onPressed: _stopSend,
                icon: const Icon(Icons.stop),
                label: const Text('إيقاف البث'),
              ),
          ] else ...[
            if (!_receiving && !_finalizing)
              FilledButton.icon(
                onPressed: _ready ? _startReceive : null,
                icon: const Icon(Icons.mic),
                label: const Text('بدء الاستماع'),
              ),
            if (_receiving)
              FilledButton.tonalIcon(
                onPressed: _stopReceive,
                icon: const Icon(Icons.mic_off),
                label: const Text('إيقاف الاستماع'),
              ),
            if (_result != null)
              FilledButton.tonalIcon(
                onPressed: () => OpenFilex.open(_result!.path),
                icon: const Icon(Icons.open_in_new),
                label: const Text('فتح الملف المستلم'),
              ),
          ],
          const SizedBox(height: 16),
          if (_active) LinearProgressIndicator(
            value: _sending ? null : _progress,
          ),
          const SizedBox(height: 8),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(_status),
          )),
          const SizedBox(height: 8),
          const Text(
            'تجريبي: نقل الصوت بطيء جداً. يتطلب اختباراً على هاتفين حقيقيين. '
            'لا تشارك كلمة المرور في قناة الصوت.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      )),
    );
  }
}
