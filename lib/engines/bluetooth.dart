import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/transfer.dart';

/// Bonded, secure Android RFCOMM. No BLE/network fallback.
class BluetoothEngine extends TransferEngine {
 BluetoothEngine({Future<bool> Function()? permission}) : _permission=permission??_requestPermission;
 static const methods=MethodChannel('app.viadrop/bluetooth');
 static final _events=const EventChannel('app.viadrop/bluetooth-events')
     .receiveBroadcastStream(const {'observer':true});
 static int _next=0;
 final int _id=++_next;
 final Future<bool> Function() _permission;
 bool _disposed=false;
 int? _generation;
 Future<void>? _stopping;
 Stream<dynamic> get events=>_events.where((e)=>!_disposed&&e is Map&&e['clientId']==_id&&
     (_generation==null||e['generation']==_generation));
 static Future<bool> _requestPermission()async {
  final info=await methods.invokeMapMethod<String,dynamic>('info');
  if(info?['supported']!=true)return false;
  if((info?['sdk'] as int? ?? 0)<31)return true;
  final grants=await [Permission.bluetoothConnect,Permission.bluetoothScan].request();
  return grants.values.every((p)=>p.isGranted);
 }
 void _check(){if(_disposed)throw const TransferCancelled();}
 @override Channel get channel=>Channel.bluetooth;
 @override Capabilities get capabilities=>const Capabilities(discovery:true);
 @override Future<bool> checkAvailability()async=>
     (await methods.invokeMapMethod<String,dynamic>('info'))?['supported']==true;
 @override Future<void> initialize()async {
  _check();final granted=await _permission();_check();
  if(!granted)throw StateError('Bluetooth permission denied');
 }
 @override Stream<Peer> discover()async* {
  _check();final list=await methods.invokeListMethod<dynamic>('peers')??[];_check();
  for(final p in list){yield Peer(p['id'] as String,p['name'] as String);}
 }
 Future<void> _start(String method,[Map<String,dynamic> extra=const {}])async {
  _check();if(_stopping!=null)await _stopping;_check();_generation=null;
  try {
   final result=await methods.invokeMapMethod<dynamic,dynamic>(method,{'clientId':_id,...extra});
   _check();_generation=result?['generation'] as int?;
  }on PlatformException catch(e){if(e.code=='BT_CANCELLED')throw const TransferCancelled();rethrow;}
 }
 @override Future<void> receive()=>_start('listen');
 @override Future<void> send(File file,Peer? peer,CancelToken token,void Function(int,int) progress)async {
  if(peer==null)throw ArgumentError('Select a paired device');token.check();_check();
  final sub=events.listen((e){if(e['type']=='progress'&&!token.cancelled)progress((e['done'] as num).toInt(),(e['total'] as num).toInt());});
  try{await _start('startSend',{'address':peer.id,'path':file.path});token.check();}
  finally{await sub.cancel();}
 }
 Future<void> decide(int decisionId,bool accept)async {
  _check();await methods.invokeMethod<void>('decision',{'clientId':_id,'decisionId':decisionId,'accept':accept});
 }
 Future<void> openSettings()=>methods.invokeMethod<void>('settings');
 @override Future<void> cancel(){
  return _stopping??=_stop();
 }
 Future<void> _stop()async {
  try{await methods.invokeMethod<void>('stop',{'clientId':_id});}
  finally{_generation=null;_stopping=null;}
 }
 @override Future<void> dispose()async{_disposed=true;await cancel();}
}
