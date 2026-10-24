import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/transfer.dart';
class NativeBridge {
 static const methods=MethodChannel('app.viadrop/native');
 static final events=const EventChannel('app.viadrop/events').receiveBroadcastStream().asBroadcastStream();
 static Future<void> play(Uint8List data,bool high)async=>methods.invokeMethod('audioPlay',{'data':data,'high':high});
 static Future<void> listen()async{if(!await Permission.microphone.request().isGranted)throw StateError('Microphone permission denied');await methods.invokeMethod('audioListen');}
 static Future<void> stopAudio()async=>methods.invokeMethod('audioStop');
}
class BluetoothEngine extends TransferEngine {
 @override Channel get channel=>Channel.bluetooth;
 @override Capabilities get capabilities=>const Capabilities(discovery:true);
 @override Future<bool> checkAvailability()async=>(await NativeBridge.methods.invokeMethod<bool>('btAvailable'))??false;
 @override Future<void> initialize()async{
  await [Permission.bluetoothScan,Permission.bluetoothConnect].request();
  if(!await checkAvailability())throw StateError('Enable Bluetooth in Android settings');
 }
 @override Stream<Peer> discover()async*{
  final list=await NativeBridge.methods.invokeListMethod<dynamic>('btPeers')??[];
  for(final p in list){yield Peer(p['address'] as String,p['name'] as String);}
 }
 @override Future<void> send(File f,Peer? peer,CancelToken token,void Function(int,int) progress)async{
  if(peer==null)throw ArgumentError('Select paired device');token.check();final sub=NativeBridge.events.listen((e){if(e['type']=='btProgress')progress(e['done'] as int,e['total'] as int);});
  try{await NativeBridge.methods.invokeMethod('btSend',{'address':peer.id,'path':f.path});}finally{await sub.cancel();}
 }
 @override Future<void> receive()async=>NativeBridge.methods.invokeMethod('btListen');
 @override Future<void> cancel()async=>NativeBridge.methods.invokeMethod('btStop');
 @override Future<void> dispose()=>cancel();
}
