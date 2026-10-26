import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/core/audio_diagnostics.dart';
void main(){
 test('no metrics is not reported as a working microphone',(){
  final d=AudioDiagnostics();expect(d.recording,false);expect(d.report,contains('لم تصل قياساته بعد'));
 });
 test('silent samples are distinguished from undecodable nonzero signal',(){
  final d=AudioDiagnostics();
  d.metrics({'samples':48000,'elapsedMs':1000,'windowSamples':48000,'peak':0,'recording':true,'inputRouteType':15});
  expect(d.report,contains('صامتة رقمياً'));expect(d.routeName,'ميكروفون الهاتف');
  d.metrics({'samples':96000,'elapsedMs':2000,'windowSamples':48000,'peak':2000,'rmsDbfs':-30,'clipped':480,'recording':true,'nativePackets':0});
  expect(d.clippedPercent,1);expect(d.report,contains('لم يفك حزمة بعد'));expect(d.report,contains('48000 عينة/s'));
 });
 test('decoder counts and UI counts remain distinct; no payload is retained',(){
  final d=AudioDiagnostics();d.metrics({'nativePackets':3,'samples':48000,'elapsedMs':1000,'peak':1000});
  d.packets=2;d.probes=1;d.starts=1;
  expect(d.report,contains('المحرك: 3'));expect(d.report,contains('للواجهة: 2'));expect(d.report,contains('اختبار الرابط: 1'));
 });
}
