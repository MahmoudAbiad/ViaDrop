import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'core/manager.dart';
import 'core/transfer.dart';
import 'engines/lan.dart';
import 'engines/native.dart';

/// Real LAN and paired-Bluetooth transport UI. Physical modes remain disabled
/// until their camera/speaker pipelines are wired and tested on devices.
class RadioTransferPage extends StatefulWidget {
  const RadioTransferPage({
    super.key,
    required this.manager,
    required this.channel,
  });

  final TransferManager manager;
  final Channel channel;

  @override
  State<RadioTransferPage> createState() => _RadioTransferPageState();
}

class _RadioTransferPageState extends State<RadioTransferPage> {
  final _pass = TextEditingController();
  final _ip = TextEditingController();
  final _message = TextEditingController();
  final Map<String, Peer> _peers = {};
  TransferEngine? _engine;
  StreamSubscription<Peer>? _peerSub;
  StreamSubscription<dynamic>? _nativeSub;
  Peer? _peer;
  File? _selected;
  String? _acceptedPass;
  String _notice = 'أدخل عبارة مرور متطابقة على الجهازين (12 حرفاً على الأقل).';
  bool _ready = false;
  bool _listening = false;
  bool _busy = false;
  bool _sending = false;
  int _done = 0;
  int _total = 0;

  bool get _wifi => widget.channel == Channel.wifi;
  String get _label => _wifi ? 'Wi-Fi المحلي' : 'Bluetooth';
  String get _passValue => _pass.text.trim();

  @override
  void initState() {
    super.initState();
    unawaited(_setup());
  }

  Future<void> _setup() async {
    try {
      final TransferEngine engine;
      if (_wifi) {
        engine = LanEngine(
          directory: widget.manager.work,
          consent: _offer,
          onFile: (file) => _saveIncoming(file, Channel.wifi),
          onProgress: _incomingProgress,
          onError: (error) => _show('خطأ Wi-Fi: ' + error.toString()),
        );
      } else {
        engine = BluetoothEngine();
        _nativeSub = NativeBridge.events.listen(_handleNativeEvent,
            onError: (Object error) => _show(error.toString()));
      }
      _engine = engine;
      await engine.initialize();
      _peerSub = engine.discover().listen((peer) {
        if (!mounted) return;
        setState(() => _peers[peer.id] = peer);
      });
      if (!mounted) return;
      setState(() {
        _ready = true;
        _notice = _wifi
            ? 'متصل بالشبكة المحلية. فعّل الاستقبال على الجهاز الآخر.'
            : 'اقرن الجهازين من إعدادات Android ثم حدّث الأجهزة.';
      });
    } catch (e) {
      _show('تعذرت تهيئة ' + _label + ': ' + e.toString());
    }
  }

  bool _validPass() {
    if (_passValue.length >= 12) return true;
    _show('عبارة المرور المطلوبة 12 حرفاً على الأقل، ويجب أن تتطابق على الجهازين.');
    return false;
  }

  Future<bool> _offer(String sender, int bytes) async {
    if (!mounted || !_listening || _busy || _passValue.length < 12) {
      return false;
    }
    final passAtOffer = _passValue;
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('طلب استقبال ملف'),
        content: Text('من: ' + sender + '\nالحجم المشفّر: ' +
            _size(bytes) + '\nلن يُحفظ الملف قبل فك التشفير والتحقق منه.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رفض'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('قبول'),
          ),
        ],
      ),
    );
    if (choice == true && mounted) {
      _acceptedPass = passAtOffer;
      setState(() => _notice = 'يتم استقبال بيانات مشفّرة من ' + sender);
    }
    return choice == true && mounted;
  }

  Future<void> _saveIncoming(File file, Channel channel) async {
    if (!mounted) throw StateError('Receiver closed');
    final pass = _acceptedPass;
    if (pass == null || _busy) throw StateError('No accepted transfer');
    setState(() {
      _busy = true;
      _sending = false;
      _notice = 'جاري فك التشفير والتحقق من الملف...';
    });
    try {
      widget.manager.begin();
      widget.manager.update(Phase.waiting);
      final output = await widget.manager.accept(file, pass, channel);
      _show('تم استلام الملف بنجاح: ' + output.uri.pathSegments.last);
    } catch (e) {
      _show('لم يُحفظ الملف: فشل التحقق أو عبارة المرور غير صحيحة: ' +
          e.toString());
      rethrow;
    } finally {
      _acceptedPass = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  void _incomingProgress(int done, int total) {
    if (!mounted || _sending) return;
    setState(() {
      _done = done;
      _total = total;
    });
  }

  void _handleNativeEvent(dynamic raw) {
    if (!mounted || raw is! Map) return;
    final type = raw['type'];
    if (type == 'error') {
      _show('Bluetooth: ' + (raw['message'] ?? 'خطأ').toString());
    } else if (type == 'btOffer') {
      unawaited(_offer(
        (raw['name'] ?? 'جهاز قريب').toString(),
        (raw['size'] as num).toInt(),
      ).then((accepted) async {
        await NativeBridge.methods.invokeMethod<void>(
            'btAccept', {'accept': accepted});
      }).catchError((Object error) {
        _show('تعذّر الرد على طلب Bluetooth: ' + error.toString());
      }));
    } else if (type == 'btProgress' && !_sending) {
      _incomingProgress((raw['done'] as num).toInt(),
          (raw['total'] as num).toInt());
    } else if (type == 'btFile') {
      unawaited(_handleBluetoothFile((raw['path'] ?? '').toString()));
    }
  }

  Future<void> _handleBluetoothFile(String path) async {
    bool success = false;
    try {
      if (path.isEmpty) throw const FormatException('Missing file');
      await _saveIncoming(File(path), Channel.bluetooth);
      success = true;
    } catch (_) {
      // _saveIncoming reports why a transfer was rejected.
    } finally {
      try {
        await NativeBridge.methods
            .invokeMethod<void>('btAccept', {'accept': success});
      } catch (e) {
        _show('تعذّر تأكيد استلام Bluetooth: ' + e.toString());
      }
    }
  }

  Future<void> _toggleReceive() async {
    if (!_ready || _busy || _engine == null) return;
    if (_listening) {
      setState(() => _listening = false);
      if (!_wifi) await _engine!.cancel();
      _show('تم إيقاف استقبال الطلبات.');
      return;
    }
    if (!_validPass()) return;
    try {
      await _engine!.receive();
      if (mounted) setState(() {
        _listening = true;
        _notice = 'الاستقبال نشط. استخدم نفس عبارة المرور على الجهاز المرسل.';
      });
    } catch (e) {
      _show('تعذر تشغيل الاستقبال: ' + e.toString());
    }
  }

  Future<void> _pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.any, withData: false);
      final path = result?.files.single.path;
      if (!mounted || path == null) return;
      setState(() => _selected = File(path));
    } catch (e) {
      _show('تعذر فتح الملف: ' + e.toString());
    }
  }

  Future<void> _makeTextFile() async {
    if (_message.text.trim().isEmpty) return;
    final f = File(widget.manager.work.path + '/note-' +
        DateTime.now().microsecondsSinceEpoch.toString() + '.txt');
    await f.writeAsString(_message.text);
    if (mounted) setState(() => _selected = f);
  }

  Future<void> _refresh() async {
    if (!_ready || _engine == null) return;
    if (_wifi) {
      try {
        await (_engine! as LanEngine).refreshDiscovery();
        _show('تم بث طلب الاكتشاف. تأكد من أن الجهازين على نفس الشبكة.');
      } catch (e) {
        _show('تعذّر تحديث اكتشاف Wi-Fi: $e');
      }
      return;
    }
    if (!_wifi) {
      try {
        final peers = await _engine!.discover().toList();
        if (mounted) setState(() {
          _peers
            ..clear()
            ..addEntries(peers.map((e) => MapEntry(e.id, e)));
        });
      } catch (e) {
        _show('تعذر تحديث الأجهزة: ' + e.toString());
      }
    }
  }

  Peer? _destination() {
    if (_wifi && _ip.text.trim().isNotEmpty) {
      final ip = _ip.text.trim();
      return Peer(ip, ip);
    }
    return _peer;
  }

  Future<void> _send() async {
    if (_busy || !_ready || _engine == null || _selected == null) return;
    if (!_validPass()) return;
    final peer = _destination();
    if (peer == null) {
      _show(_wifi ? 'اختر جهازاً أو أدخل عنوان IPv4 المحلي.'
          : 'اختر جهاز Bluetooth مقترناً.');
      return;
    }
    File? sealed;
    setState(() {
      _busy = true;
      _sending = true;
      _done = 0;
      _total = 0;
      _notice = 'جار تجهيز الملف المشفّر...';
    });
    try {
      widget.manager.begin();
      sealed = await widget.manager.prepare(_selected!, _passValue);
      if (!mounted) return;
      final size = await sealed.length();
      widget.manager.update(Phase.transferring, total: size);
      setState(() {
        _total = size;
        _notice = 'يتم الإرسال إلى ' + peer.name;
      });
      await _engine!.send(sealed, peer, widget.manager.token, (done, total) {
        if (!mounted) return;
        widget.manager.update(Phase.transferring, done: done, total: total);
        setState(() {
          _done = done;
          _total = total;
        });
      });
      widget.manager.update(Phase.completed);
      await widget.manager.record(_selected!, widget.channel, 'sent');
      _show('نجح الإرسال. تم تأكيد استلام البيانات المشفّرة.');
    } catch (e) {
      _show('فشل الإرسال: ' + e.toString());
    } finally {
      if (sealed != null && await sealed.exists()) await sealed.delete();
      if (mounted) setState(() {
        _busy = false;
        _sending = false;
      });
    }
  }

  void _show(String text) {
    if (mounted) setState(() => _notice = text);
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return (bytes / 1024).toStringAsFixed(1) + ' KB';
    }
    return (bytes / (1024 * 1024)).toStringAsFixed(1) + ' MB';
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    _nativeSub?.cancel();
    unawaited(_engine?.dispose() ?? Future<void>.value());
    _pass.dispose();
    _ip.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? (_done / _total).clamp(0.0, 1.0) : null;
    return Scaffold(
      appBar: AppBar(title: Text(_label)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text('نقل مشفّر بين جهازين', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('هذه نسخة اختبار أولية. يتطلب النقل تثبيت ViaDrop على الجهازين.'),
          const SizedBox(height: 14),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'عبارة المرور المشتركة (12 حرفاً على الأقل)',
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _ready && !_busy ? _toggleReceive : null,
                icon: Icon(_listening ? Icons.stop : Icons.download),
                label: Text(_listening ? 'إيقاف الاستقبال' : 'تفعيل الاستقبال'),
              ),
            ),
            if (!_wifi) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'إعدادات اقتران Bluetooth',
                onPressed: () => NativeBridge.methods
                    .invokeMethod<void>('btSettings'),
                icon: const Icon(Icons.settings_bluetooth),
              ),
            ],
          ]),
          const Divider(height: 30),
          Row(children: [
            Expanded(child: Text('إرسال', style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
              tooltip: 'تحديث الأجهزة',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ]),
          OutlinedButton.icon(
            onPressed: _ready && !_busy ? _pick : null,
            icon: const Icon(Icons.attach_file),
            label: Text(_selected?.uri.pathSegments.last ?? 'اختر ملفاً'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _message,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'أو اكتب نصاً لإرساله',
              suffixIcon: IconButton(
                tooltip: 'تجهيز النص كملف',
                icon: const Icon(Icons.note_add_outlined),
                onPressed: _makeTextFile,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          if (_wifi) ...[
            TextField(
              controller: _ip,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'عنوان IPv4 المحلي (اختياري عند اكتشاف الجهاز)',
                hintText: '192.168.1.20',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_peers.isNotEmpty) ...[
            const Text('الأجهزة المكتشفة أو المقترنة:'),
            ..._peers.values.map((peer) => RadioListTile<String>(
              title: Text(peer.name),
              subtitle: Text(peer.id),
              value: peer.id,
              groupValue: _peer?.id,
              onChanged: _busy ? null : (_) => setState(() => _peer = peer),
            )),
          ] else Text(
            _wifi ? 'لم يتم اكتشاف أجهزة بعد. يمكنك إدخال IP يدوياً.'
                : 'لا توجد أجهزة مقترنة. افتح إعدادات Bluetooth أولاً.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _ready && !_busy && _selected != null ? _send : null,
            icon: const Icon(Icons.send),
            label: const Text('إرسال الملف فعلياً'),
          ),
          const SizedBox(height: 16),
          if (progress != null) ...[
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
            Text(_size(_done) + ' / ' + _size(_total)),
            const SizedBox(height: 10),
          ],
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(_notice),
          )),
          const SizedBox(height: 20),
          const Text('ملاحظة: لم يكتمل اختبار التوافق بين هاتفين. '
              'لا تستخدم هذه النسخة لنقل بيانات حساسة قبل الاختبار الأمني.'),
        ],
      ),
    );
  }
}
