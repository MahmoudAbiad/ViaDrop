import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/main.dart';

void main(){
 testWidgets('home exposes all four channels and honest capability labels',(tester)async{
  tester.view.physicalSize=const Size(1080,2400);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const ViaDropApp());await tester.pumpAndSettle();
  expect(find.text('بالكاميرا • QR'),findsOneWidget);
  expect(find.text('بالصوت'),findsOneWidget);
  expect(find.text('Wi-Fi • شبكة محلية'),findsOneWidget);
  expect(find.text('Bluetooth Classic'),findsOneWidget);
  expect(find.textContaining('Wi-Fi Direct وWi-Fi Aware غير متاحين'),findsOneWidget);
 });
}
