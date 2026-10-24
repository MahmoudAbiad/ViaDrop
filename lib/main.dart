import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/manager.dart';
import 'core/transfer.dart';
import 'radio_transfer_page.dart';
import 'screens/qr_transfer_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ViaDropApp());
}

class ViaDropApp extends StatelessWidget {
  const ViaDropApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ViaDrop',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3667F6)),
      fontFamily: 'Cairo',
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF101827),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF31D6CA),
        brightness: Brightness.dark,
      ),
      fontFamily: 'Cairo',
    ),
    themeMode: ThemeMode.system,
    home: const RecoveryHome(),
  );
}

class RecoveryHome extends StatefulWidget {
  const RecoveryHome({super.key});
  @override
  State<RecoveryHome> createState() => _RecoveryHomeState();
}

class _RecoveryHomeState extends State<RecoveryHome> {
  final TransferManager manager = TransferManager();
  final TextEditingController passphrase = TextEditingController();
  File? selected;
  bool ready = false;
  bool busy = false;
  String message = 'هذه نسخة استعادة تجريبية. قنوات النقل لم تُختبر بعد على هاتفين.';

  @override
  void initState() {
    super.initState();
    manager.initialize().then((_) {
      if (mounted) setState(() => ready = true);
    }).catchError((Object e) {
      if (mounted) setState(() => message = 'فشل التهيئة: $e');
    });
  }

  @override
  void dispose() {
    passphrase.dispose();
    manager.dispose();
    super.dispose();
  }

  Future<void> selectFile() async {
    try {
      final files = await FilePicker.platform.pickFiles(withData: false);
      if (!mounted || files == null || files.files.isEmpty) return;
      final path = files.files.single.path;
      if (path == null) throw const FileSystemException('مسار الملف غير متاح');
      setState(() {
        selected = File(path);
        message = 'اختر عبارة مرور ثم جرّب إنشاء ملف مشفّر محلياً.';
      });
    } catch (e) {
      if (mounted) setState(() => message = 'خطأ في اختيار الملف: $e');
    }
  }

  Future<void> encryptLocally() async {
    if (!ready || busy || selected == null) return;
    if (passphrase.text.length < 12) {
      setState(() => message = 'عبارة المرور يجب أن تكون 12 حرفاً على الأقل.');
      return;
    }
    setState(() => busy = true);
    try {
      manager.begin();
      manager.update(Phase.transferring);
      final result = await manager.prepare(selected!, passphrase.text);
      manager.update(Phase.completed);
      final size = await result.length();
      if (mounted) {
        setState(() => message = 'نجح تجهيز ملف مشفّر ($size بايت). لم يُرسل إلى أي جهاز.');
      }
    } catch (e) {
      if (mounted) setState(() => message = 'فشل اختبار التشفير: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void showChannel(Channel channel) {
    if (channel == Channel.wifi || channel == Channel.bluetooth) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => RadioTransferPage(manager: manager, channel: channel),
      ));
      return;
    }
    if (channel == Channel.qr) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QrTransferPage()));
      return;
    }
    final label = switch (channel) {
      Channel.wifi => 'Wi-Fi',
      Channel.bluetooth => 'Bluetooth',
      Channel.qr => 'QR / Camera',
      Channel.audio => 'Audio',
    };
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text('القناة البصرية/الصوتية لم تربط بعد بواجهة إرسال واستقبال، ولا نعرض نجاحاً وهمياً.'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ViaDrop'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  colors: [Color(0xFF3667F6), Color(0xFF31D6CA)],
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.hub_rounded, color: Colors.white, size: 38),
                  SizedBox(height: 12),
                  Text('شاركها بأي طريقة.', style: TextStyle(
                    color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
                  Text('Share beyond connections.', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Wi-Fi وBluetooth للتجربة — QR والصوت قيد الاستعادة', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(label: const Text('Wi-Fi'), avatar: const Icon(Icons.wifi),
                  onPressed: () => showChannel(Channel.wifi)),
                ActionChip(label: const Text('Bluetooth'), avatar: const Icon(Icons.bluetooth),
                  onPressed: () => showChannel(Channel.bluetooth)),
                ActionChip(label: const Text('QR'), avatar: const Icon(Icons.qr_code),
                  onPressed: () => showChannel(Channel.qr)),
                ActionChip(label: const Text('Audio'), avatar: const Icon(Icons.graphic_eq),
                  onPressed: () => showChannel(Channel.audio)),
              ],
            ),
            const SizedBox(height: 22),
            Text('اختبار تشفير محلي — يعمل دون شبكة', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: ready && !busy ? selectFile : null,
              icon: const Icon(Icons.attach_file),
              label: Text(selected?.uri.pathSegments.last ?? 'اختر ملفاً'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passphrase,
              obscureText: true,
              enableSuggestions: false,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'عبارة مرور (12 حرفاً على الأقل)',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: ready && !busy && selected != null ? encryptLocally : null,
              icon: const Icon(Icons.lock_outline),
              label: Text(busy ? 'يجري التشفير...' : 'تجهيز الملف المشفّر'),
            ),
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(message))),
            const SizedBox(height: 30),
            Text('Recovery Preview — ليس إصدار مشاركة ملفات مكتملاً',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
