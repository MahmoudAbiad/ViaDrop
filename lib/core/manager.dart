import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'transfer.dart';
import 'vault.dart';
class TransferManager extends ChangeNotifier {
 bool _disposed=false;
 void _notify(){if(!_disposed)notifyListeners();}
 bool _stale(CancelToken operation)=>_disposed||operation.cancelled||!identical(operation,token);
 TransferStatus status=const TransferStatus(Phase.idle);CancelToken token=CancelToken();SessionState state=SessionState();
 List<Map<String,dynamic>> history=[];late Directory work,received;final clock=Stopwatch();
 double get bytesPerSecond=>clock.elapsedMilliseconds>0?status.done*1000/clock.elapsedMilliseconds:0;
 Future<void> initialize()async{
  final sessions=Directory('${(await getTemporaryDirectory()).path}/sessions');await sessions.create(recursive:true);
  work=await sessions.createTemp('session-');
  received=Directory('${(await getApplicationDocumentsDirectory()).path}/Received');await received.create(recursive:true);
  // Each route owns staging; never delete another route's in-flight files.
  final prefs=await SharedPreferences.getInstance();try{history=(jsonDecode(prefs.getString('history')??'[]') as List).map((e)=>Map<String,dynamic>.from(e)).toList();}catch(_){history=[];}
 }
 void update(Phase phase,{int done=0,int total=0,String message=''}){
  if(_disposed)throw const TransferCancelled();
  if(phase==Phase.transferring&&status.phase!=phase){clock.reset();clock.start();}
  if(phase!=Phase.transferring)clock.stop();
  state.transition(phase);status=TransferStatus(phase,done:done,total:total,message:message);_notify();
 }
 void begin(){if(_disposed)throw const TransferCancelled();token=CancelToken();state=SessionState();update(Phase.preparing);}
 Future<File> prepare(File f,String pass)async{
  if(_disposed)throw const TransferCancelled();
  final operation=token;
  final source=f.path,target='${work.path}/${DateTime.now().microsecondsSinceEpoch}.vdp';
  final result=await _sealIsolated(source,target,pass);
  if(_stale(operation)){if(await result.exists())await result.delete();throw const TransferCancelled();}return result;
 }
 Future<File> accept(File encrypted,String pass,Channel channel)async{
  final operation=token;
  update(Phase.verifying);final source=encrypted.path,dest=received.path;
  final result=await _openIsolated(source,dest,pass);
  if(_stale(operation)){await result.delete();throw const TransferCancelled();}
  // Verification is complete. Once history commit begins, preserve this valid
  // file even if its screen closes; only UI notification is suppressed.
  await record(result,channel,'received');
  if(!_stale(operation))update(Phase.completed,message:result.path);
  return result;
 }
 Future<void> record(File f,Channel c,String result)async{
  history.insert(0,{'name':f.uri.pathSegments.last,'path':result=='received'?f.path:null,'size':await f.length(),'channel':c.name,'result':result,'time':DateTime.now().toIso8601String()});
  if(history.length>200)history.removeRange(200,history.length);await(await SharedPreferences.getInstance()).setString('history',jsonEncode(history));_notify();
 }
 Future<void> clearHistory()async{history.clear();await(await SharedPreferences.getInstance()).remove('history');_notify();}
 void cancel(){token.cancelled=true;if(!_disposed)update(Phase.cancelled);}
 @override void dispose(){if(_disposed)return;_disposed=true;token.cancelled=true;super.dispose();}
}

// These closures have only string arguments in their lexical context, rather
// than a manager/notifier and its route callbacks crossing the isolate boundary.
Future<File> _sealIsolated(String source,String target,String password) =>
 Isolate.run(()=>Vault.seal(File(source),File(target),password,CancelToken()));
Future<File> _openIsolated(String source,String destination,String password) =>
 Isolate.run(()=>Vault.open(File(source),Directory(destination),password,CancelToken()));
