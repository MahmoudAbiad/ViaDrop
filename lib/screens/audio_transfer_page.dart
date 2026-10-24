import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/acoustic_pairing.dart';
import '../core/audio_estimate.dart';
import '../core/qr_pairing.dart';
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
  final _text = TextEditingController();
  StreamSubscription<dynamic>? _events;
  OpticalPairing? _pairing;
  Future<void>? _beaconTask;
  Future<void>? _replyTask;
  Future<void>? _readyTask;
  // One acoustic transmitter per turn. A beacon opens a silent reply window.
  bool _invitationBusy = false;
  bool _replyBusy = false;
  String? _acceptedInvitation;
  int _handshakeEpoch = 0;
  Completer<void>? _beaconWake;
  bool _pairingSender = false;
  bool _identityConfirmed = false;
  bool _senderReady = false;
  bool _pairingReceiver = false;
  bool _answerBusy = false;
  String? _acceptedReply;
  File? _source;
  int _sourceBytes = 0;
  File? _result;
  PhysicalDecoder _decoder = PhysicalDecoder(64 * 1024);
  CancelToken? _sendToken;
  bool _ready = false;
  bool _receiving = false;
  // Protect the asynchronous microphone-permission/startup window.
  bool _listenStarting = false;
  bool _listenStopping = false;
  bool _sending = false;
  bool _finalizing = false;
  bool _highFrequency = false;
  bool _fastAudio = true;
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

  bool get _active =>
      _receiving || _pairingSender || _senderReady || _listenStarting || _listenStopping || _sending || _finalizing;

  Future<void> _pick() async {
    try {
      final files = await FilePicker.platform.pickFiles(withData: false);
      if (files == null || files.files.isEmpty || !mounted) return;
      final path = files.files.single.path;
      if (path == null) throw const FileSystemException('Missing file path');
      final size = await File(path).length();
      if (!mounted) return;
      setState(() {
        _source = File(path);
        _sourceBytes = size;
      });
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
    if (!_ready || _sending || !_identityConfirmed || _pairing?.passphrase == null) {
      _show('لم يكتمل الاقتران الصوتي.');
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
      // The acoustic modem is low-bandwidth. A larger experimental cap
      // enables short notes/documents; it does not make large files fast.
      if (await input.length() > 48 * 1024) {
        throw StateError('حجم الملف يتجاوز الحد التجريبي للصوت (48KB).');
      }
      _manager.begin();
      encrypted = await _manager.prepare(input, _pairing!.passphrase!);
      if (token.cancelled) return;
      if (await encrypted.length() > 64 * 1024) {
        throw StateError('حجم البيانات بعد التشفير أكبر من حد الصوت (64KB).');
      }
      await WakelockPlus.enable();
      wakeLockActive = true;
      _manager.update(Phase.transferring);
      _show('جارٍ الإرسال الصوتي. قد يستغرق نقل ملف كبير عدة دقائق. '
          'اترك الهاتفين متقاربين وانتظر اكتمال الاستقبال.');
      final engine = PhysicalEngine(
        Channel.audio,
        sessionId: _pairing!.sessionId,
        emit: (Uint8List packet) => NativeBridge.play(packet, _highFrequency, fast: _fastAudio),
        stopListening: NativeBridge.stopAudio,
      )..audioBlockLength = _fastAudio ? 900 : 100;
      await engine.send(encrypted, null, token, (sent, total) {
        if (mounted) {
          setState(() {
            // Frames repeat until the sender stops. A full round does not
            // mean the receiver has reconstructed and verified the file.
            _progress = ((sent % total) / total).clamp(0, 1);
          });
        }
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
    if ((_pairingSender || _senderReady) && !_sending) {
      await _stopReceive();
      _show('تم إلغاء الاقتران الصوتي.');
      return;
    }
    _sendToken?.cancelled = true;
    try {
      await NativeBridge.stopAudio();
    } catch (error) {
      _show('فشل إيقاف الصوت: ' + error.toString());
    }
  }

  Future<void> _beginAudioSendPairing() async {
    if (!_ready || _active) return;
    setState(() => _listenStarting = true);
    try {
      if (_text.text.trim().isEmpty && _source == null) {
        throw StateError('اكتب نصاً أو اختر ملفاً أولاً');
      }
      await WakelockPlus.enable();
      ++_handshakeEpoch;
      _pairing = null;
      _acceptedInvitation = null;
      _invitationBusy = false;
      _replyBusy = false;
      _replyTask = null;
      _readyTask = null;
      _identityConfirmed = false;
      _senderReady = false;
      _events = NativeBridge.events.listen(
        _handleEvent,
        onError: (Object error) =>
            unawaited(_failReceive('خطأ في الاقتران الصوتي: $error')),
      );
      await NativeBridge.listen(fast: _fastAudio);
      if (!mounted) {
        await NativeBridge.stopAudio();
        return;
      }
      setState(() {
        _pairingSender = true;
        _status = 'ننتظر إشارة الاقتران من الجهاز المستقبل. '
            'اضغط استقبال على الجهاز الثاني، وقرب الهاتفين.';
      });
    } catch (error) {
      await _stopReceive();
      _show('فشل الاقتران الصوتي: $error');
    } finally {
      if (mounted) setState(() => _listenStarting = false);
    }
  }

  // ggwave decodes a complete invitation near the end of its playback.
  // The receiver must leave the entire following turn silent so the sender's
  // reply is not masked by another invitation. A valid reply ends the wait.
  Future<void> _beaconLoop(OpticalPairing pairing) async {
    final bytes = Uint8List.fromList(utf8.encode(pairing.invitation));
    final wake = _beaconWake;
    while (_receiving && _pairingReceiver &&
        identical(_pairing, pairing) && pairing.passphrase == null) {
      try {
        // Pairing always uses the audible, older-device-compatible modem.
        await NativeBridge.play(bytes, false);
        await Future.any<void>([
          Future<void>.delayed(const Duration(milliseconds: 4800)),
          if (wake != null) wake.future,
        ]);
      } catch (error) {
        if (_receiving && _pairingReceiver &&
            identical(_pairing, pairing)) {
          unawaited(_failReceive('فشل إرسال الاقتران: $error'));
        }
        return;
      }
    }
  }

  // Reply only to a received invitation, never on a free-running timer.
  // Another identical invitation means the previous reply was lost.
  Future<void> _replyOnce(OpticalPairing pairing) async {
    if (_replyBusy || !_pairingSender || !identical(_pairing, pairing)) return;
    _replyBusy = true;
    try {
      // Let the remote speaker finish before taking our transmit turn.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!_pairingSender || !identical(_pairing, pairing)) return;
      await NativeBridge.play(
        Uint8List.fromList(utf8.encode(pairing.reply)), false,
      );
    } catch (error) {
      if (_pairingSender && identical(_pairing, pairing)) {
        unawaited(_failReceive('فشل إرسال رد الاقتران: $error'));
      }
    } finally {
      if (identical(_pairing, pairing)) _replyBusy = false;
    }
  }

  Future<void> _receiveInvitation(String invitation) async {
    if (!_pairingSender || !mounted) return;
    final existing = _pairing;
    if (existing != null) {
      if (invitation == _acceptedInvitation && !_replyBusy) {
        _replyTask = _replyOnce(existing);
      }
      return;
    }
    if (_invitationBusy) return;
    _invitationBusy = true;
    final epoch = _handshakeEpoch;
    try {
      final pairing = await OpticalPairing.acceptInvitation(invitation);
      if (pairing == null || !_pairingSender || !mounted ||
          _pairing != null || epoch != _handshakeEpoch) return;
      _pairing = pairing;
      _acceptedInvitation = invitation;
      _show('وصل الاقتران. نرسل الرد ثم نستمع لتأكيد المستقبل...');
      _replyTask = _replyOnce(pairing);
    } finally {
      if (epoch == _handshakeEpoch) _invitationBusy = false;
    }
  }

  // Receiver repeats READY only while no file frame has been detected.
  // This fixes a lost READY without colliding with an ongoing file transfer.
  Future<void> _readyLoop(OpticalPairing pairing) async {
    final bytes = Uint8List.fromList(
      utf8.encode(AcousticReady.token(pairing)),
    );
    while (_receiving && _pairingReceiver && _identityConfirmed &&
        identical(_pairing, pairing) && _decoder.header == null) {
      try {
        await NativeBridge.play(bytes, false);
        // The sender needs time to hear READY and begin its first file frame.
        await Future<void>.delayed(const Duration(seconds: 8));
      } catch (error) {
        if (_receiving && identical(_pairing, pairing)) {
          unawaited(_failReceive('فشل إرسال تأكيد الاقتران: $error'));
        }
        return;
      }
    }
  }

  Future<void> _finishSenderPairing(String ready) async {
    final pair = _pairing;
    if (!_pairingSender || pair?.passphrase == null ||
        !AcousticReady.verify(pair!, ready)) return;
    _pairingSender = false;
    _listenStarting = true;
    await _replyTask;
    if (!mounted || _pairing != pair || !_listenStarting) return;
    try {
      await NativeBridge.stopAudio();
      await _events?.cancel();
      _events = null;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _listenStarting = false;
        _senderReady = true;
        _status = 'أكد تطابق البصمة على الهاتفين لبدء بث الملف.';
      });
    }
  }

  Future<void> _acceptAcousticReply(String response) async {
    final pair = _pairing;
    if (!_pairingReceiver || pair == null || _answerBusy) return;
    if (_acceptedReply != null && _acceptedReply != response) return;
    _answerBusy = true;
    try {
      if (_acceptedReply == null) {
        if (!await pair.acceptReply(response)) return;
        _acceptedReply = response;
        // End the beacon's silent reply window immediately on valid receipt.
        if (_beaconWake != null && !_beaconWake!.isCompleted) {
          _beaconWake!.complete();
        }
        await _beaconTask;
        if (!_receiving || !mounted || !identical(_pairing, pair)) return;
        _decoder = PhysicalDecoder(
          64 * 1024, expectedSessionId: pair.sessionId,
        );
      }
      if (!_identityConfirmed) {
        _show('قارن بصمة الاقتران مع الجهاز المرسل ثم أكد التطابق.');
        return;
      }
      _readyTask ??= _readyLoop(pair);
      if (mounted && _receiving) {
        _show('تم تأكيد البصمة. نرسل إشارة الجاهزية وننتظر الملف...');
      }
    } catch (error) {
      if (_receiving) _show('تعذّر تأكيد الاقتران: $error');
    } finally {
      _answerBusy = false;
    }
  }

  Future<void> _startReceive() async {
    if (!_ready || _active) {
      _show('الجهاز مشغول بجلسة صوتية أخرى.');
      return;
    }
    // Guard immediately, before waiting for the screen-lock plugin or the
    // asynchronous Android microphone permission prompt.
    setState(() => _listenStarting = true);
    try {
      ++_handshakeEpoch;
      _pairing = await OpticalPairing.createSender();
      _acceptedReply = null;
      _acceptedInvitation = null;
      _beaconWake = Completer<void>();
      _beaconTask = null;
      _replyTask = null;
      _readyTask = null;
      _invitationBusy = false;
      _replyBusy = false;
      _identityConfirmed = false;
      _senderReady = false;
      _answerBusy = false;
      _decoder = PhysicalDecoder(64 * 1024);
      _manager.begin();
      _manager.update(Phase.waiting);
      _events = NativeBridge.events.listen(
        _handleEvent,
        onError: (Object error) =>
            unawaited(_failReceive('خطأ في استقبال الصوت: $error')),
      );
      await WakelockPlus.enable();
      if (!mounted) {
        await _events?.cancel();
        _events = null;
        await WakelockPlus.disable();
        return;
      }
      setState(() {
        _receiving = true;
        _pairingReceiver = true;
        _progress = 0;
        _result = null;
        _status = 'جارٍ تشغيل الاقتران الصوتي...';
      });
      await NativeBridge.listen(fast: _fastAudio);
      // Stop can be pressed while permission_handler is still waiting for
      // the user. Do not leave an orphan microphone session when the native
      // call returns after the receiver was cancelled or disposed.
      if (!mounted || !_receiving) {
        await NativeBridge.stopAudio();
      } else {
        _show('يرسل المستقبل إشارة اقتران قصيرة. اضغط إرسال في الجهاز الثاني.');
        _beaconTask = _beaconLoop(_pairing!);
      }
    } catch (error) {
      await _stopReceive();
      _show('تعذّر فتح الميكروفون: $error');
    } finally {
      if (mounted) setState(() => _listenStarting = false);
    }
  }

  void _handleEvent(dynamic data) {
    if ((!_receiving && !_pairingSender) || _finalizing || data is! Map) return;
    if (data['type'] == 'error') {
      unawaited(_failReceive(
        'المودم الصوتي: ' + (data['message'] ?? 'خطأ').toString(),
      ));
      return;
    }
    if (data['type'] != 'audioData') return;
    final raw = data['data'];
    if (raw is! List<int>) return;
    final bytes = Uint8List.fromList(raw);

    if (_pairingSender) {
      final text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith(OpticalPairing.invitePrefix)) {
        unawaited(_receiveInvitation(text));
      } else if (text.startsWith(AcousticReady.prefix)) {
        unawaited(_finishSenderPairing(text));
      }
      return;
    }

    if (_pairingReceiver) {
      final text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith(OpticalPairing.replyPrefix)) {
        unawaited(_acceptAcousticReply(text));
        return;
      }
      if (_pairing?.passphrase == null || !_identityConfirmed) return;
    }

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
          _status = 'تم تجاهل إرسال تالف. ما زلنا نستمع لإرسال جديد.';
        });
      } else {
        _show('إطار صوتي غير صالح: $error');
      }
    }
  }

  Future<void> _failReceive(String message) async {
    if (!_receiving && !_pairingSender) return;
    await _stopReceive();
    _show(message);
  }

  Future<void> _finishReceive(Uint8List encryptedData) async {
    File? temp;
    try {
      temp = File(_manager.work.path + '/audio-' +
          DateTime.now().microsecondsSinceEpoch.toString() + '.vdp');
      await temp.writeAsBytes(encryptedData, flush: true);
      final received = await _manager.accept(temp, _pairing!.passphrase!, Channel.audio);
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
    // Invalidate the UI before awaiting any native call, but keep the
    // stopping guard active until all resources have been released.
    if (_listenStopping) return;
    _listenStopping = true;
    ++_handshakeEpoch;
    if (_beaconWake != null && !_beaconWake!.isCompleted) {
      _beaconWake!.complete();
    }
    _beaconWake = null;
    _acceptedInvitation = null;
    _readyTask = null;
    _replyTask = null;
    _listenStarting = false;
    _pairingSender = false;
    _pairingReceiver = false;
    _senderReady = false;
    _identityConfirmed = false;
    if (mounted) setState(() => _receiving = false);
    try {
      try { await NativeBridge.stopAudio(); } catch (_) {}
      await _events?.cancel();
      _events = null;
      try { await WakelockPlus.disable(); } catch (_) {}
    } finally {
      _listenStopping = false;
      if (mounted) setState(() => _receiving = false);
    }
  }

  @override
  void dispose() {
    _sendToken?.cancelled = true;
    ++_handshakeEpoch;
    if (_beaconWake != null && !_beaconWake!.isCompleted) {
      _beaconWake!.complete();
    }
    _pairingSender = false;
    _pairingReceiver = false;
    _events?.cancel();
    NativeBridge.stopAudio();
    unawaited(WakelockPlus.disable());
    _text.dispose();
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _text.text.trim().isNotEmpty
        ? utf8.encode(_text.text).length : _sourceBytes;
    final estimate = AudioEstimate.forInputBytes(bytes, fast: _fastAudio);
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
          const Text(
            'الاقتران آلي بإشارات صوتية قصيرة؛ لا تحتاج إلى رمز تشفير.',
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('صوت سريع OFDM • تجريبي'),
            subtitle: const Text('فعّله على الجهازين. يستخدم صوتاً مسموعاً؛ '
                'لم يُختبر بعد على هاتفين. لا يوجد تبديل خفي إلى الشبكة.'),
            value: _fastAudio,
            onChanged: _active ? null : (value) => setState(() => _fastAudio = value),
          ),
          if (_sendMode) ...[
            TextField(
              controller: _text,
              onChanged: (_) => setState(() {}),
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
            if (_source != null || _text.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(bytes > 48 * 1024
                    ? 'الحجم يتجاوز حد الصوت التجريبي (48KB).'
                    : 'تقدير مبدئي: ${estimate.lowerMinutes}–${estimate.upperMinutes} دقيقة. '
                      'لا يشمل الاقتران، وقد يزيد مع الضجيج أو فقد الإشارات.'),
              ),
            SwitchListTile(
              title: const Text('الترددات العالية (للوضع البطيء)'),
              subtitle: const Text('قد لا تدعمها سماعة أو ميكروفون بعض الهواتف.'),
              value: _highFrequency,
              onChanged: _active || _fastAudio ? null : (value) => setState(() => _highFrequency = value),
            ),
            if (!_sending && !_pairingSender && !_senderReady)
              FilledButton.icon(
                onPressed: _ready && !_active && bytes <= 48 * 1024
                    ? _beginAudioSendPairing : null,
                icon: const Icon(Icons.volume_up),
                label: const Text('إرسال • اقتران صوتي تلقائي'),
              ),
            if (_sending || _pairingSender || _senderReady)
              FilledButton.tonalIcon(
                onPressed: _stopSend,
                icon: const Icon(Icons.stop),
                label: const Text('إيقاف البث'),
              ),
          ] else ...[
            if (!_receiving && !_finalizing)
              FilledButton.icon(
                onPressed: _ready && !_listenStarting ? _startReceive : null,
                icon: const Icon(Icons.mic),
                label: const Text('استقبال • اقتران صوتي تلقائي'),
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
          if (_active && _pairing?.verificationCode != null) ...[
            const SizedBox(height: 12),
            const Text('قارن البصمة على الهاتفين. ألغِ العملية إذا اختلفت.'),
            SelectableText(_pairing!.verificationCode!,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            if (!_identityConfirmed)
              FilledButton.icon(
                onPressed: _sendMode && !_senderReady ? null : () {
                  setState(() => _identityConfirmed = true);
                  if (_sendMode) {
                    setState(() => _senderReady = false);
                    unawaited(_startSend());
                  } else {
                    // The sender repeats its reply until this authenticated
                    // ready token arrives; a lost ready is retried normally.
                    final reply = _acceptedReply;
                    if (reply != null) unawaited(_acceptAcousticReply(reply));
                  }
                },
                icon: const Icon(Icons.verified_user),
                label: Text(_sendMode && !_senderReady
                    ? 'بانتظار تأكيد المستقبل'
                    : 'البصمتان متطابقتان • متابعة'),
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
            'تجريبي: يدعم الصوت الآن ملفات حتى 48KB قبل التشفير. '
            'الملفات الأكبر قد تستغرق وقتاً طويلاً جداً، '
            'ومؤشر المرسل يوضح دورة الإطارات وليس نجاح الاستلام. '
            'الاقتران الصوتي التلقائي تجريبي ويحتاج تجربة على هاتفين.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      )),
    );
  }
}
