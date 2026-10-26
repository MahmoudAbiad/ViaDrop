import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/qr_transfer_page.dart';
import 'screens/audio_transfer_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final entry in const {
      'Cyrinx': ['Cyrinx-Apache-2.0.txt', 'Cyrinx-NOTICE.txt'],
      'KISS FFT': ['KISS-FFT-BSD.txt'],
      'ggwave': ['ggwave-MIT.txt'],
      'Reed-Solomon': ['ReedSolomon-MIT.txt'],
      'Ooura FFT': ['Ooura.txt'],
      'OneSend': ['OneSend.txt', 'OneSend-NOTICES.md'],
      'Cairo': ['Cairo-OFL.txt'],
      'Manrope': ['Manrope-OFL.txt'],
    }.entries) {
      for (final file in entry.value) {
        yield LicenseEntryWithLineBreaks([entry.key],
            await rootBundle.loadString('assets/licenses/$file'));
      }
    }
  });
  LicenseRegistry.addLicense(() async* {
    // Generated only by the pinned color packaging step. Source-only/test
    // checkouts can omit it; a shipped color APK is checked for its manifest.
    try {
      final files = jsonDecode(await rootBundle.loadString('assets/licenses/color/INDEX.json')) as List;
      for (final file in files.whereType<String>()) {
        if (file.endsWith('.json')) continue;
        yield LicenseEntryWithLineBreaks(['ViaDrop color / CIMBAR / OpenCV'],
          await rootBundle.loadString(file));
      }
    } on FlutterError { /* Color distribution assets absent in source tests. */ }
  });
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
    home: const ViaDropHome(),
  );
}

class ViaDropHome extends StatelessWidget {
  const ViaDropHome({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ViaDrop'), centerTitle: true,
        actions: [IconButton(
          tooltip: 'تراخيص البرمجيات',
          icon: const Icon(Icons.info_outline),
          onPressed: () => showLicensePage(context: context, applicationName: 'ViaDrop'),
        )]),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [
                Color(0xFF3667F6), Color(0xFF31D6CA),
              ]),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.hub_rounded, color: Colors.white, size: 38),
                SizedBox(height: 12),
                Text('شاركها بأي طريقة.', style: TextStyle(
                  color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold,
                )),
                Text('Share beyond connections.',
                  style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text('كيف تحب تشارك؟', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.qr_code_scanner)),
              title: const Text('بالكاميرا • QR'),
              subtitle: const Text('امسح رمز الاقتران ثم انقل الملف عبر الشاشة.'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => _open(context, const QrTransferPage()),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.graphic_eq)),
              title: const Text('بالصوت'),
              subtitle: const Text('صوت سريع تجريبي • اقتران تلقائي ومقارنة بصمة.'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => _open(context, const AudioTransferPage()),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'لا تحتاج كلمة مرور أو إنترنت. المفاتيح تُنشأ تلقائياً '
            'لكل عملية نقل، ويظل المحتوى مشفّراً.',
          ),
          const SizedBox(height: 8),
          const Text(
            'ميزات الكاميرا والصوت تجريبية ويجب التحقق منها بين هاتفين. '
            'الواي فاي والبلوتوث سيأتيان في إصدار لاحق.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      )),
    );
  }
}
