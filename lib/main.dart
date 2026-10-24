import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/qr_transfer_page.dart';
import 'screens/audio_transfer_page.dart';

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
      appBar: AppBar(title: const Text('ViaDrop'), centerTitle: true),
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
              subtitle: const Text('قرّب الجهازين واتركهما يتقارنان تلقائياً.'),
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
