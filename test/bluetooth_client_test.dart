import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/core/transfer.dart';
import 'package:viadrop/engines/bluetooth.dart';

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 final calls=<MethodCall>[];
 setUp((){
  calls.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(BluetoothEngine.methods,(call)async{
   calls.add(call);
   switch(call.method){
    case 'info':return {'sdk':23,'supported':true};
    case 'peers':return [{'id':'AA:BB:CC:DD:EE:FF','name':'paired test device'}];
    case 'listen':return {'generation':1};
    default:return null;
   }
  });
 });
 test('paired devices are enumerated without starting a transport',()async{
  final engine=BluetoothEngine(permission:()async=>true);
  await engine.initialize();final peers=await engine.discover().toList();
  expect(peers.single.id,'AA:BB:CC:DD:EE:FF');
  expect(calls.map((c)=>c.method),['peers']);await engine.dispose();
 });
 test('dispose while permission is pending never starts a listener',()async{
  final permission=Completer<bool>();final engine=BluetoothEngine(permission:()=>permission.future);
  final init=engine.initialize();final failure=expectLater(init,throwsA(isA<TransferCancelled>()));
  await engine.dispose();permission.complete(true);await failure;
  expect(calls.where((c)=>c.method=='listen'),isEmpty);
 });
 test('permission denial prevents native session',()async{
  final engine=BluetoothEngine(permission:()async=>false);
  await expectLater(engine.initialize(),throwsStateError);expect(calls,isEmpty);await engine.dispose();
 });
 test('decisions carry operation identity and exact request ID',()async{
  final first=BluetoothEngine(permission:()async=>true),second=BluetoothEngine(permission:()async=>true);
  await first.decide(50,true);await second.decide(51,false);
  final a=calls[0].arguments as Map,b=calls[1].arguments as Map;
  expect(a['clientId'],isNot(b['clientId']));expect(a['decisionId'],50);expect(b['accept'],false);
  await first.dispose();await second.dispose();
 });
 test('concurrent stops join one native cleanup',()async{
  final cleanup=Completer<void>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(BluetoothEngine.methods,(call)async{calls.add(call);if(call.method=='stop')await cleanup.future;return null;});
  final engine=BluetoothEngine(permission:()async=>true);final a=engine.cancel(),b=engine.cancel();
  await Future<void>.delayed(Duration.zero);expect(calls.length,1);cleanup.complete();await Future.wait([a,b]);
 });
 test('cancelled token prevents sending before native work',()async{
  final engine=BluetoothEngine(permission:()async=>true);final token=CancelToken()..cancelled=true;
  await expectLater(engine.send(File('not-opened'),const Peer('paired','test'),token,(_,__){}),throwsA(isA<TransferCancelled>()));
  expect(calls,isEmpty);await engine.dispose();
 });
}
