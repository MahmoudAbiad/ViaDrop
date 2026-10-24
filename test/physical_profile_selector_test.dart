import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/core/physical_profiles.dart';
import 'package:viadrop/widgets/physical_profile_selector.dart';

void main() {
  const capabilities = PhysicalCapabilities(
    probeOk: true,
    camera: true,
    cameraMaxFps: 15,
    displayHz: 60,
    microphone: false,
    audioInput48k: false,
    audioOutput48k: false,
    ofdmNative: false,
    ultrasoundInput: false,
    ultrasoundOutput: false,
  );

  testWidgets('dropdown shows planned and unsupported modes as disabled',
      (tester) async {
    String? choice;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: PhysicalProfileSelector(
          medium: PhysicalMedium.qr,
          capabilities: capabilities,
          selectedId: 'qr-standard',
          enabled: true,
          checking: false,
          onChanged: (value) => choice = value,
          onRefresh: () {},
        )),
      ),
    ));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ultra Optical'), findsWidgets);
    expect(find.textContaining('High-Density QR'), findsWidgets);
    expect(find.textContaining('QR Fast'), findsWidgets);
    expect(choice, isNull);
    final menu = tester.widgetList<DropdownMenuItem<String>>(
        find.byType(DropdownMenuItem<String>));
    final disabled = menu.where((item) => item.value == 'qr-fast').toList();
    expect(disabled, isNotEmpty);
    expect(disabled.first.enabled, isFalse);
  });
}
