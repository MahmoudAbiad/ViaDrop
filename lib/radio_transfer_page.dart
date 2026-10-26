import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'core/manager.dart';
import 'core/screen_awake.dart';
import 'core/transfer.dart';
import 'engines/lan.dart';
import 'engines/bluetooth.dart';
import 'package:open_filex/open_filex.dart';

/// Owns a manager for this route; no other screen's token is cancelled.
class RadioTransferEntry extends StatefulWidget {
 const RadioTransferEntry({super.key,required this.channel});
 final Channel channel;
 @override State<RadioTransferEntry> createState()=>_RadioTransferEntryState();
}
class _RadioTransferEntryState extends State<RadioTransferEntry> {
 final _manager=TransferManager();
 late final Future<void> _ready=_manager.initialize();
 @override void dispose(){_manager.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>FutureBuilder<void>(future:_ready,builder:(context,snapshot){
  if(snapshot.hasError)return Scaffold(appBar:AppBar(title:const Text('ViaDrop')),body:Center(child:Text('تعذّر تجهيز التخزين: ${snapshot.error}')));
  if(snapshot.connectionState!=ConnectionState.done)return const Scaffold(body:Center(child:CircularProgressIndicator()));
  return RadioTransferPage(manager:_manager,channel:widget.channel);
 });
}

/// Real LAN and paired Bluetooth, explicitly experimental until device tests.
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

class _RadioTransferPageState extends State<RadioTransferPage> with WidgetsBindingObserver {
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
  BuildContext? _offerContext;
  WakeLockLease? _receiveAwake;
  WakeLockLease? _sendAwake;
  int _operation=0;
  bool _offerPending=false;
  bool _verifying=false;
  bool _stopping=false;
  File? _received;
  File? _note;
  final _clock=Stopwatch();
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
    WidgetsBinding.instance.addObserver(this);
    unawaited(_setup());
  }

  Future<void> _setup() async {
    final operation=_operation;
    try {
      final TransferEngine engine;
      if (_wifi) {
        engine = LanEngine(
          directory: widget.manager.work,
          consent: _offer,
          onFile: (file) => _saveIncoming(file, Channel.wifi),
          onProgress: _incomingProgress,
          onError: _transportError,
        );
      } else {
        engine = BluetoothEngine();
        _nativeSub = engine.events.listen(_handleNativeEvent,
            onError: (Object error) => _show(error.toString()));
      }
      _engine = engine;
      await engine.initialize();
      if(!mounted||operation!=_operation){await engine.dispose();return;}
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
    if (!mounted || !_listening || _busy || _offerPending || _stopping || _passValue.length < 12) {
      return false;
    }
    final operation=_operation;
    _offerPending=true;
    final passAtOffer = _passValue;
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) { _offerContext=ctx; return AlertDialog(
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
      );},
    ).timeout(const Duration(seconds:55),onTimeout:(){_dismissOffer();return false;});
    _offerContext=null;
    _offerPending=false;
    if (choice == true && mounted && operation==_operation && _listening && !_stopping) {
      _acceptedPass = passAtOffer;
      setState(() {_busy=true;_sending=false;_done=0;_total=bytes;_clock.reset();_clock.start();_notice = 'يتم استقبال بيانات مشفّرة من ' + sender;});
      return true;
    }
    return false;
  }

  Future<void> _saveIncoming(File file, Channel channel) async {
    if (!mounted) throw StateError('Receiver closed');
    final operation=_operation;
    final pass = _acceptedPass;
    if (pass == null || !_busy || _sending || _verifying) throw StateError('No accepted transfer');
    setState(() {
      _busy = true;
      _verifying=true;
      _sending = false;
      _notice = 'جاري فك التشفير والتحقق من الملف...';
    });
    try {
      widget.manager.begin();
      widget.manager.update(Phase.waiting);
      final output = await widget.manager.accept(file, pass, channel);
      if(!mounted||operation!=_operation)throw const TransferCancelled();
      setState(()=>_received=output);
      _show('تم استلام الملف بنجاح: ' + output.uri.pathSegments.last);
    } catch (e) {
      if(operation==_operation)_show('لم يُحفظ الملف: فشل التحقق أو عبارة المرور غير صحيحة: ' +
          e.toString());
      rethrow;
    } finally {
      if(operation==_operation){
       _acceptedPass = null;
       if (mounted) setState(() {_busy = false;_verifying=false;});
      }
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
    if (type == 'error'||type=='stopped') {
      _transportError(raw['message']??'Bluetooth stopped');
      if(type=='stopped'){setState(()=>_listening=false);unawaited(_receiveAwake?.dispose()??Future<void>.value());_receiveAwake=null;}
    } else if (type == 'offer') {
      unawaited(_offer(
        (raw['name'] ?? 'جهاز قريب').toString(),
        (raw['size'] as num).toInt(),
      ).then((accepted) async {
        if(mounted)await (_engine! as BluetoothEngine).decide((raw['decisionId'] as num).toInt(),accepted);
      }).catchError((Object error) {
        _show('تعذّر الرد على طلب Bluetooth: ' + error.toString());
      }));
    } else if (type == 'progress' && !_sending) {
      _incomingProgress((raw['done'] as num).toInt(),
          (raw['total'] as num).toInt());
    } else if (type == 'file') {
      unawaited(_handleBluetoothFile((raw['path'] ?? '').toString(),(raw['decisionId'] as num).toInt()));
    }
  }

  Future<void> _handleBluetoothFile(String path,int decisionId) async {
    bool success = false;
    try {
      if (path.isEmpty) throw const FormatException('Missing file');
      await _saveIncoming(File(path), Channel.bluetooth);
      success = true;
    } catch (_) {
      // _saveIncoming reports why a transfer was rejected.
    } finally {
      try {
        if(mounted)await (_engine! as BluetoothEngine).decide(decisionId,success);
      } catch (e) {
        _show('تعذّر تأكيد استلام Bluetooth: ' + e.toString());
      }
    }
  }

  Future<void> _toggleReceive() async {
    if (!_ready || _busy || _stopping || _engine == null) return;
    if (_listening) {
      setState(() => _listening = false);
      await _stop();
      _show('تم إيقاف استقبال الطلبات.');
      return;
    }
    if (!_validPass()) return;
    final operation=_operation;
    final awake=ScreenAwake.lease();_receiveAwake=awake;
    try {
      await awake.acquire();
      if(!mounted||operation!=_operation)throw const TransferCancelled();
      await _engine!.receive();
      if(!mounted||operation!=_operation)throw const TransferCancelled();
      if (mounted) setState(() {
        _listening = true;
        _notice = 'الاستقبال نشط. استخدم نفس عبارة المرور على الجهاز المرسل.';
      });
    } catch (e) {
      await awake.dispose();if(identical(_receiveAwake,awake))_receiveAwake=null;
      if(operation==_operation)_show('تعذر تشغيل الاستقبال: ' + e.toString());
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
    if(_note!=null&&await _note!.exists())await _note!.delete();
    _note=f;
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
    final awake=ScreenAwake.lease();_sendAwake=awake;
    final operation=++_operation;
    setState(() {
      _busy = true;
      _sending = true;
      _done = 0;
      _total = 0;
      _notice = 'جار تجهيز الملف المشفّر...';
    });
    try {
      await awake.acquire();
      if(!mounted||operation!=_operation)throw const TransferCancelled();
      widget.manager.begin();
      sealed = await widget.manager.prepare(_selected!, _passValue);
      if (!mounted||operation!=_operation)throw const TransferCancelled();
      final size = await sealed.length();
      widget.manager.token.check();_clock.reset();_clock.start();
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
      _show('نجح الإرسال. أكّد المستقبل فك التشفير وسلامة الملف.');
    } catch (e) {
      if(operation==_operation)_show('توقف الإرسال: ' + e.toString());
    } finally {
      await awake.dispose();if(identical(_sendAwake,awake))_sendAwake=null;
      if (sealed != null && await sealed.exists()) await sealed.delete();
      if (mounted&&operation==_operation) setState(() {
        _busy = false;
        _sending = false;
      });
    }
  }

  void _transportError(Object error){
    if(!mounted||_stopping)return;
    _dismissOffer();
    if(!_sending&&!_verifying)setState((){_busy=false;_acceptedPass=null;});
    _show('خطأ النقل: $error');
  }

  void _dismissOffer(){final dialog=_offerContext;_offerContext=null;if(dialog!=null&&dialog.mounted)Navigator.of(dialog).pop(false);}

  Future<void> _stop()async {
    if(_stopping)return;
    ++_operation;widget.manager.cancel();_dismissOffer();
    final receiveAwake=_receiveAwake;_receiveAwake=null;final sendAwake=_sendAwake;_sendAwake=null;
    setState((){_stopping=true;_ready=false;_listening=false;_acceptedPass=null;});
    try{
      await receiveAwake?.dispose();await sendAwake?.dispose();
      await _engine?.cancel();
      await _peerSub?.cancel();await _nativeSub?.cancel();
      await _engine?.dispose();_engine=null;
      if(mounted){setState((){_busy=false;_sending=false;_verifying=false;_stopping=false;_done=0;_total=0;});await _setup();}
    }catch(e){if(mounted){setState(()=>_stopping=false);_show('تعذر إيقاف النقل: $e');}}
  }

  @override void didChangeAppLifecycleState(AppLifecycleState state){
    // Allow visiting Bluetooth settings when idle; stop real sessions in background.
    if((state==AppLifecycleState.paused||state==AppLifecycleState.detached)&&(_busy||_listening))unawaited(_stop());
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
    WidgetsBinding.instance.removeObserver(this);
    ++_operation;widget.manager.cancel();
    _peerSub?.cancel();
    _nativeSub?.cancel();
    unawaited(_receiveAwake?.dispose()??Future<void>.value());
    unawaited(_sendAwake?.dispose()??Future<void>.value());
    unawaited(_engine?.dispose() ?? Future<void>.value());
    final note=_note;if(note!=null)unawaited(note.exists().then((exists)async{if(exists)await note.delete();}));
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
          Text(_wifi?'نقل محلي عبر الراوتر أو نقطة اتصال، دون إنترنت. ليس Wi-Fi Direct.':'Bluetooth Classic / RFCOMM عبر اقتران Android الآمن، دون شبكة Wi-Fi.'),
          if(_wifi&&_engine is LanEngine)Text('عناوين هذا الجهاز: ${(_engine! as LanEngine).localAddresses.join(' • ')}'),
          if(!_ready&&!_stopping)TextButton.icon(onPressed:_stop,icon:const Icon(Icons.refresh),label:const Text('إعادة التهيئة بعد تفعيل Bluetooth أو الشبكة')),
          const SizedBox(height: 14),
          TextField(
            controller: _pass,
            enabled: !_busy&&!_offerPending&&!_stopping,
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
                onPressed: _busy||_stopping?null:()=>(_engine as BluetoothEngine?)?.openSettings(),
                icon: const Icon(Icons.settings_bluetooth),
              ),
            ],
          ]),
          const Divider(height: 30),
          Row(children: [
            Expanded(child: Text('إرسال', style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
              tooltip: 'تحديث الأجهزة',
              onPressed: _ready&&!_busy&&!_stopping?_refresh:null,
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
            enabled: !_busy&&!_stopping,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'أو اكتب نصاً لإرساله',
              suffixIcon: IconButton(
                tooltip: 'تجهيز النص كملف',
                icon: const Icon(Icons.note_add_outlined),
                onPressed: _busy||_stopping?null:_makeTextFile,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          if (_wifi) ...[
            TextField(
              controller: _ip,
              enabled: !_busy&&!_stopping,
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
            onPressed: _ready && !_busy && !_listening && !_stopping && _selected != null ? _send : null,
            icon: const Icon(Icons.send),
            label: const Text('إرسال الملف فعلياً'),
          ),
          if(_busy||_listening)OutlinedButton.icon(onPressed:_stopping?null:_stop,icon:const Icon(Icons.cancel_outlined),label:Text(_stopping?'جار الإيقاف...':'إلغاء النقل والاستقبال')),
          if(_received!=null)TextButton.icon(onPressed:()=>OpenFilex.open(_received!.path),icon:const Icon(Icons.open_in_new),label:const Text('فتح الملف المستقبَل')),
          const SizedBox(height: 16),
          if (progress != null) ...[
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
            Text(_size(_done) + ' / ' + _size(_total)),
            if(_clock.elapsedMilliseconds>0&&_done>0)Text('${_size((_done*1000/_clock.elapsedMilliseconds).round())}/s • المتبقي تقريباً ${((_total-_done)*_clock.elapsedMilliseconds/_done/1000).ceil()} ثانية'),
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
