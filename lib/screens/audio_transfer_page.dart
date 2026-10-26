import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../core/screen_awake.dart';

import '../core/audio_estimate.dart';
import '../core/manager.dart';
import '../core/one_way_session.dart';
import '../core/physical_profiles.dart';
import '../widgets/physical_profile_selector.dart';
import '../core/transfer.dart';
import '../engines/native.dart';
import '../engines/physical.dart';

/// One-way acoustic transport. Receiver ONLY listens; there is no acoustic
/// response, no X25519 round trip and no manual verification code.
/// The audible start packet carries the secret so nearby listeners are not
/// cryptographically excluded from the broadcast.
class AudioTransferPage extends StatefulWidget {
  const AudioTransferPage({super.key});

  @override
  State<AudioTransferPage> createState() => _AudioTransferPageState();
}

class _AudioTransferPageState extends State<AudioTransferPage> {
  final _manager = TransferManager();
  final _awake = ScreenAwake.lease();
  final _text = TextEditingController();
  StreamSubscription<dynamic>? _events;
  OneWaySession? _session;
  File? _source;
  int _sourceBytes = 0;
  File? _result;
  PhysicalDecoder _decoder = PhysicalDecoder(64 * 1024);
  CancelToken? _sendToken;
  bool _ready = false;
  bool _receiving = false;
  bool _listenStarting = false;
  bool _listenStopping = false;
  bool _sending = false;
  bool _finalizing = false;
  PhysicalCapabilities _capabilities = const PhysicalCapabilities.unavailable();
  String? _profileId;
  bool _probing = true;
  bool _sendMode = true;
  double _progress = 0;
  String _status = 'استقبال صوتي صامت: يبدأ تلقائياً عند وصول رسالة البدء.';

  bool get _active => _receiving || _listenStarting ||
      _listenStopping || _sending || _finalizing;

  @override
  void initState() {
    super.initState();
    unawaited(_probeCapabilities());
    _manager.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((Object e) {
      _show('فشل التهيئة: $e');
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
        _profileId = result.recommended(PhysicalMedium.audio)?.id;
      }
      _probing = false;
    });
  }

  PhysicalProfile? get _profile =>
      _profileId == null ? null : physicalProfileById(_profileId!);

  bool get _profileSupported =>
      _profile != null && _capabilities.availability(_profile!).enabled;

  void _show(String message) {
    if (mounted) setState(() => _status = message);
  }

  Future<void> _pick() async {
    if (_active) return;
    try {
      final selection = await FilePicker.platform.pickFiles(withData: false);
      if (selection == null || selection.files.isEmpty || !mounted) return;
      final path = selection.files.single.path;
      if (path == null) throw const FileSystemException('Missing file path');
      final size = await File(path).length();
      if (mounted) setState(() {
        _source = File(path);
        _sourceBytes = size;
      });
    } catch (error) {
      _show('تعذر اختيار الملف: $error');
    }
  }

  Future<File?> _inputFile() async {
    if (_text.text.trim().isNotEmpty) {
      final file = File('${_manager.work.path}/audio-note-${DateTime.now().microsecondsSinceEpoch}.txt');
      await file.writeAsString(_text.text);
      return file;
    }
    return _source;
  }

  /// The sender broadcasts the start packet; no answer is expected.
  Future<void> _startSend() async {
    if (!_ready || _active || !_profileSupported) return;
    if (_text.text.trim().isEmpty && _source == null) {
      _show('اكتب نصاً أو اختر ملفاً أولاً.');
      return;
    }
    final profile = _profile!;
    final token = CancelToken();
    _sendToken = token;
    final session = OneWaySession.create(profileId: profile.id);
    _session = session;
    var wakeLockActive = false;
    File? encrypted;
    setState(() {
      _sending = true;
      _progress = 0;
      _status = 'جارٍ تجهيز الملف، ثم بث رسالة البدء تلقائياً...';
    });
    try {
      final input = await _inputFile();
      if (input == null) throw StateError('لا يوجد ملف للإرسال');
      if (await input.length() > 48 * 1024) {
        throw StateError('الحد التجريبي للنقل الصوتي 48KB.');
      }
      _manager.begin();
      encrypted = await _manager.prepare(input, session.passphrase);
      token.check();
      if (await encrypted.length() > 64 * 1024) {
        throw StateError('الملف المشفّر تجاوز 64KB.');
      }
      await _awake.acquire();
      wakeLockActive = true;
      token.check();
      // The introduction uses audible ggwave even in the OFDM data mode.
      // Repeating it twice and between fountain rounds lets late/missed
      // listeners join without requiring a reverse acoustic channel.
      final hello = session.audioAnnouncement;
      await NativeBridge.play(hello, false);
      token.check();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      token.check();
      await NativeBridge.play(hello, false);
      token.check();
      _manager.update(Phase.transferring);
      _show('جارٍ بث الملف عبر الصوت. المستقبل يستمع فقط ولا يرد.');
      var frames = 0;
      final engine = PhysicalEngine(
        Channel.audio,
        sessionId: session.sessionId,
        emit: (Uint8List packet) async {
          token.check();
          // Only one speaker is active; periodically announce the session
          // again so dropped start packets don't block the entire transfer.
          if (++frames % 24 == 0) {
            await NativeBridge.play(hello, false);
            token.check();
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          await NativeBridge.play(packet, profile.audioHigh, fast: profile.audioFast);
        },
        stopListening: NativeBridge.stopAudio,
      )..audioBlockLength = profile.audioBlockBytes
       ..audioFrameGapMs = profile.audioFrameGapMs;
      await engine.send(encrypted, null, token, (sent, total) {
        if (mounted && total > 0) {
          setState(() => _progress = ((sent % total) / total).clamp(0, 1));
        }
      });
    } on TransferCancelled {
      _show('أوقفت البث. لا يوجد تأكيد رجوعي من المستقبل.');
    } catch (error) {
      _show('فشل الإرسال الصوتي: $error');
    } finally {
      if (wakeLockActive) {
        try { await _awake.release(); } catch (_) {}
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
      _show('فشل إيقاف الصوت: $error');
    }
  }

  Future<void> _startReceive() async {
    if (!_ready || _active || !_profileSupported) {
      _show('الجهاز مشغول أو التقنية غير مدعومة.');
      return;
    }
    setState(() => _listenStarting = true);
    try {
      _session = null;
      _result = null;
      _decoder = PhysicalDecoder(64 * 1024);
      _manager.begin();
      _manager.update(Phase.waiting);
      _events = NativeBridge.events.listen(
        _handleEvent,
        onError: (Object error) =>
            unawaited(_failReceive('خطأ في استقبال الصوت: $error')),
      );
      await _awake.acquire();
      if (!mounted) {
        await _events?.cancel();
        _events = null;
        await _awake.release();
        return;
      }
      setState(() {
        _receiving = true;
        _progress = 0;
        _status = 'نستمع فقط. اضغط إرسال على الهاتف الثاني.';
      });
      await NativeBridge.listen(fast: _profile!.audioFast);
      if (!mounted || !_receiving) {
        await NativeBridge.stopAudio();
      }
    } catch (error) {
      await _stopReceive();
      _show('تعذّر فتح الميكروفون: $error');
    } finally {
      if (mounted) setState(() => _listenStarting = false);
    }
  }

  void _handleEvent(dynamic event) {
    if (!_receiving || _finalizing || event is! Map) return;
    if (event['type'] == 'error') {
      unawaited(_failReceive('المودم الصوتي: ${event['message'] ?? 'خطأ'}'));
      return;
    }
    if (event['type'] != 'audioData') return;
    final raw = event['data'];
    if (raw is! List<int>) return;
    final bytes = Uint8List.fromList(raw);

    // Intro can arrive during initial listening or between file blocks.
    // Lock to the first valid session and reject unrelated broadcasts.
    final text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith(OneWaySession.prefix)) {
      final incoming = OneWaySession.parse(text);
      if (incoming == null) return;
      if (_session == null) {
        final other = physicalProfileById(incoming.profileId);
        if (other?.medium != PhysicalMedium.audio ||
            incoming.profileId != _profileId || !_profileSupported) {
          unawaited(_failReceive(
            'المرسل يستخدم ${other?.title ?? incoming.profileId}. '
            'اختر نفس التقنية من القائمة في الجهازين ثم أعد المحاولة.',
          ));
          return;
        }
        _session = incoming;
        _decoder = PhysicalDecoder(
          64 * 1024, expectedSessionId: incoming.sessionId,
        );
        _show('استلمنا رسالة البدء. جارٍ استقبال الملف...');
      }
      return;
    }
    if (_session == null) return;

    try {
      final complete = _decoder.add(bytes);
      if (complete == null) {
        if (mounted) setState(
          () => _progress = _decoder.progress.clamp(0, 1),
        );
        return;
      }
      _finalizing = true;
      unawaited(_finishReceive(complete));
    } catch (error) {
      if (_decoder.header == null) {
        if (mounted) setState(() {
          _progress = 0;
          _status = 'تجاهلنا إشارة تالفة وننتظر إطارات سليمة.';
        });
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
      temp = File('${_manager.work.path}/audio-${DateTime.now().microsecondsSinceEpoch}.vdp');
      await temp.writeAsBytes(encryptedData, flush: true);
      final received = await _manager.accept(
        temp, _session!.passphrase, Channel.audio,
      );
      if (mounted) setState(() {
        _result = received;
        _progress = 1;
        _status = 'تم الاستقبال والتحقق من الملف. '
            'سرعة حمولة الاستقبال: ${_decoder.payloadKiBPerSecond.toStringAsFixed(1)} KiB/s، '
            'إطارات سليمة: ${_decoder.validFrames}، '
            'إطارات مرفوضة: ${_decoder.rejectedFrames}.';
      });
    } catch (error) {
      _show('فشل فك التشفير أو فحص سلامة الملف: $error');
    } finally {
      if (temp != null && await temp.exists()) await temp.delete();
      await _stopReceive();
      if (mounted) setState(() => _finalizing = false);
    }
  }

  Future<void> _stopReceive() async {
    if (_listenStopping) return;
    _listenStopping = true;
    _listenStarting = false;
    if (mounted) setState(() => _receiving = false);
    try {
      try { await NativeBridge.stopAudio(); } catch (_) {}
      await _events?.cancel();
      _events = null;
      try { await _awake.release(); } catch (_) {}
    } finally {
      _listenStopping = false;
      if (mounted) setState(() => _receiving = false);
    }
  }

  @override
  void dispose() {
    _sendToken?.cancelled = true;
    _events?.cancel();
    NativeBridge.stopAudio();
    unawaited(_awake.dispose());
    _text.dispose();
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _text.text.trim().isNotEmpty
        ? utf8.encode(_text.text).length : _sourceBytes;
    final estimate = AudioEstimate.forInputBytes(
      bytes, fast: _profile?.audioFast ?? false,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('ViaDrop • Audio')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('سماعة المرسل ← ميكروفون المستقبل. لا تبادل صوتي.',
            style: TextStyle(fontWeight: FontWeight.w600)),
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
          const Text('المستقبل يستمع بصمت حتى يسمع رسالة بدء ثم يستقبل الملف.'),
          const SizedBox(height: 12),
          PhysicalProfileSelector(
            medium: PhysicalMedium.audio,
            capabilities: _capabilities,
            selectedId: _profileId,
            enabled: !_active,
            checking: _probing,
            onRefresh: () => unawaited(_probeCapabilities()),
            onChanged: (id) => setState(() {
              _profileId = id;
              _status = 'اضبط التقنية نفسها على الهاتف الثاني ثم ابدأ.';
            }),
          ),
          if (_sendMode) ...[
            TextField(
              controller: _text,
              onChanged: (_) => setState(() {}),
              enabled: !_active,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'اكتب نصاً قصيراً (له الأولوية على الملف المختار)',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _active ? null : _pick,
              icon: const Icon(Icons.attach_file),
              label: Text(_source?.uri.pathSegments.last ?? 'أو اختر ملفاً صغيراً'),
            ),
            if (_source != null || _text.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(bytes > 48 * 1024
                    ? 'الملف أكبر من الحد التجريبي 48KB.'
                    : 'تقدير للبيانات: ${estimate.lowerMinutes}–${estimate.upperMinutes} دقيقة، '
                      'بالإضافة إلى رسائل البدء وفقد الإشارات.'),
              ),
             if (!_sending)
              FilledButton.icon(
                onPressed: _ready && !_active && _profileSupported &&
                    bytes <= 48 * 1024 &&
                    (_text.text.trim().isNotEmpty || _source != null)
                    ? _startSend : null,
                icon: const Icon(Icons.volume_up),
                label: const Text('إرسال الصوت • بدء تلقائي'),
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
                onPressed: _ready && !_active && _profileSupported ? _startReceive : null,
                icon: const Icon(Icons.mic),
                label: const Text('استقبال • استماع صامت'),
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
          if (_active)
            LinearProgressIndicator(value: _sending ? null : _progress),
          const SizedBox(height: 8),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(_status),
          )),
          const SizedBox(height: 8),
          const Text(
            'الصوت باتجاه واحد بلا اقتران متبادل. أي جهاز قريب يسمع رسالة '
            'البدء يمكنه معرفة مفتاح الملف؛ لا تستخدمه لإرسال أسرار. '
            'الحد التجريبي 48KB، ولا يوجد تأكيد صوتي لنجاح الاستلام.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      )),
    );
  }
}
