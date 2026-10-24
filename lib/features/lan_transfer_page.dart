import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/manager.dart';
import '../core/transfer.dart';
import '../engines/lan.dart';

/// A real two-device LAN flow. Traffic carries VDP1 encrypted envelopes,
/// not cleartext user files. Both devices must agree on a passphrase.
class LanTransferPage extends StatefulWidget {
  const LanTransferPage({super.key, required this.manager, this.initialFile});
  final TransferManager manager;
  final File? initialFile;

  @override
  State<LanTransferPage> createState() => _LanTransferPageState();
}

class _LanTransferPageState extends State<LanTransferPage> {
  final _password = TextEditingController();
  final _manualIp = TextEditingController();
  final _peers = <String, Peer>{};
  LanEngine? _engine;
  StreamSubscription<Peer>? _discovery;
  File? _file;
  bool _listening = false;
  bool _busy = false;
  int _done = 0;
  int _total = 0;
  String _message = 'شغّل الاستقبال على الهاتفين، ثم اختر الجهاز المرسل إليه.';
  String _addresses = '';

  @override
  void initState() {
    super.initState();
    _file = widget.initialFile;
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final ips = interfaces.expand((i) => i.addresses)
          .where((a) => !a.isLoopback).map((a) => a.address).toSet();
      if (mounted) setState(() => _addresses = ips.join(' • '));
    } catch (_) {
      // Not fatal: Android network discovery may still work.
    }
  }

  void _progress(int done, int total) {
    if (mounted) setState(() { _done = done; _total = total; });
  }

  void _report(String value) {
    if (mounted) setState(() => _message = value);
  }

  Future<bool> _consent(String peer, int size) async {
    if (!mounted || _busy || _password.text.length < 12) {
      _report('أدخل عبارة مرور مطابقة على الجهازين (12 حرفاً على الأقل).');
      return false;
    }
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('طلب استقبال عبر Wi-Fi'),
        content: Text('الجهاز: ' + peer + '\nالحجم المشفّر: ' +
            (size / 1024).toStringAsFixed(1) + ' KB\nهل توافق على استقبال الملف؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('رفض')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('موافقة')),
        ],
      ),
    );
    return accepted == true;
  }

  Future<void> _onFile(File encrypted) async {
    if (_busy) throw StateError('Transfer already in progress');
    if (!mounted) throw StateError('Receiver closed');
    setState(() => _busy = true);
    try {
      widget.manager.begin();
      widget.manager.update(Phase.waiting);
      final saved = await widget.manager.accept(encrypted, _password.text, Channel.wifi);
      _report('تم استقبال الملف والتحقق منه وحفظه في: ' + saved.path);
    } catch (e) {
      _report('فشل التحقق أو فك تشفير الملف: ' + e.toString());
      rethrow; // Report failure to sender; never claim a successful transfer.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_listening) return;
    try {
      final engine = LanEngine(
        directory: widget.manager.work,
        consent: _consent,
        onFile: _onFile,
        onProgress: _progress,
        onError: (error) => _report('خطأ في الاتصال: ' + error.toString()),
      );
      final discovery = engine.discover().listen((peer) {
        if (mounted) setState(() => _peers[peer.id] = peer);
      });
      await engine.initialize();
      if (!mounted) {
        await discovery.cancel();
        await engine.dispose();
        return;
      }
      setState(() {
        _engine = engine;
        _discovery = discovery;
        _listening = true;
        _message = 'الاستقبال واكتشاف الأجهزة يعملان على الشبكة المحلية.';
      });
    } catch (error) {
      _report('تعذر بدء استقبال Wi-Fi: ' + error.toString());
    }
  }

  Future<void> _pick() async {
    try {
      final selection = await FilePicker.platform.pickFiles(withData: false);
      if (!mounted || selection == null || selection.files.isEmpty) return;
      final path = selection.files.single.path;
      if (path == null) throw const FileSystemException('Missing file path');
      setState(() => _file = File(path));
    } catch (error) {
      _report('تعذر اختيار الملف: ' + error.toString());
    }
  }

  Future<void> _send(Peer peer) async {
    if (_busy || _file == null) {
      _report('اختر ملفاً أولاً.');
      return;
    }
    if (_password.text.length < 12) {
      _report('أدخل نفس عبارة المرور على الهاتفين (12 حرفاً على الأقل).');
      return;
    }
    final engine = _engine;
    if (engine == null) {
      _report('ابدأ الاستقبال واكتشاف الأجهزة أولاً.');
      return;
    }
    File? encrypted;
    setState(() { _busy = true; _done = 0; _total = 0; });
    try {
      widget.manager.begin();
      _report('جارٍ تشفير الملف محلياً…');
      encrypted = await widget.manager.prepare(_file!, _password.text);
      widget.manager.update(Phase.transferring);
      _report('بانتظار موافقة الجهاز المستقبل…');
      await engine.send(encrypted, peer, widget.manager.token, _progress);
      await widget.manager.record(_file!, Channel.wifi, 'sent');
      widget.manager.update(Phase.completed);
      _report('اكتمل الإرسال، وأكد الجهاز المستقبل سلامة الملف.');
    } catch (error) {
      _report('فشل الإرسال: ' + error.toString());
    } finally {
      if (encrypted != null && await encrypted.exists()) {
        await encrypted.delete();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final engine = _engine;
    if (engine == null) return;
    await _discovery?.cancel();
    await engine.dispose();
    if (mounted) {
      setState(() {
        _engine = null;
        _discovery = null;
        _listening = false;
        _peers.clear();
        _message = 'تم إيقاف الاستقبال.';
      });
    }
  }

  @override
  void dispose() {
    _discovery?.cancel();
    _engine?.dispose();
    _password.dispose();
    _manualIp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total == 0 ? null : (_done / _total).clamp(0.0, 1.0);
    return Scaffold(
      appBar: AppBar(title: const Text('ViaDrop • Wi-Fi')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('نقل محلي مشفّر بين هاتفين على نفس شبكة Wi-Fi، دون الحاجة للإنترنت.'),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'عبارة المرور المشتركة',
              helperText: '12 حرفاً على الأقل، ويجب أن تكون نفسها على الهاتفين.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _listening ? null : _start,
            icon: const Icon(Icons.wifi),
            label: const Text('تشغيل الاستقبال واكتشاف الأجهزة'),
          ),
          if (_listening) OutlinedButton(
            onPressed: _busy ? null : _stop,
            child: const Text('إيقاف الاستقبال'),
          ),
          if (_addresses.isNotEmpty) Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SelectableText('عنوان هذا الهاتف: ' + _addresses),
          ),
          const Divider(height: 30),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.attach_file),
            label: Text(_file == null ? 'اختيار ملف للإرسال' : _file!.uri.pathSegments.last),
          ),
          const SizedBox(height: 12),
          Text('الأجهزة المكتشفة', style: Theme.of(context).textTheme.titleMedium),
          if (_peers.isEmpty) const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('لا توجد أجهزة بعد. افتح ViaDrop على الهاتف الآخر وشغّل الاستقبال.'),
          ),
          for (final peer in _peers.values)
            ListTile(
              title: Text(peer.name),
              subtitle: Text(peer.id),
              leading: const Icon(Icons.phone_android),
              trailing: const Icon(Icons.send),
              onTap: _busy ? null : () => _send(peer),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _manualIp,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'أو أدخل عنوان IP للجهاز الآخر',
              hintText: '192.168.1.10',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _send(Peer(_manualIp.text.trim(), _manualIp.text.trim())),
            icon: const Icon(Icons.send),
            label: const Text('إرسال إلى العنوان المحدد'),
          ),
          if (progress != null) Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(value: progress),
          ),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(_message),
          )),
          const SizedBox(height: 12),
          const Text('تنبيه: لا تعتبر هذه القناة مختبرة على هاتفين حتى تنجح تجربة فعلية. استخدم شبكة محلية موثوقة.'),
        ],
      )),
    );
  }
}
