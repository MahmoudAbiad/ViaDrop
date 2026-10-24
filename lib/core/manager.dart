import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'transfer.dart';
import 'vault.dart';
class TransferManager extends ChangeNotifier {
 TransferStatus status=const TransferStatus(Phase.idle);CancelToken token=CancelToken();SessionState state=SessionState();
 List<Map<String,dynamic>> history=[];late Directory work,received;final clock=Stopwatch();
 double get bytesPerSecond=>clock.elapsedMilliseconds>0?status.done*1000/clock.elapsedMilliseconds:0;
 Future<void> initialize()async{
  work=Directory('${(await getTemporaryDirectory()).path}/sessions');await work.create(recursive:true);
  received=Directory('${(await getApplicationDocumentsDirectory()).path}/Received');await received.create(recursive:true);
  await for(final f in work.list()){if(f is File)await f.delete();}
  await for(final f in received.list()){if(f is File&&f.path.endsWith('.partial'))await f.delete();}
  final prefs=await SharedPreferences.getInstance();try{history=(jsonDecode(prefs.getString('history')??'[]') as List).map((e)=>Map<String,dynamic>.from(e)).toList();}catch(_){history=[];}
 }
 void update(Phase phase,{int done=0,int total=0,String message=''}){
  if(phase==Phase.transferring&&status.phase!=phase){clock.reset();clock.start();}
  if(phase!=Phase.transferring)clock.stop();
  state.transition(phase);status=TransferStatus(phase,done:done,total:total,message:message);notifyListeners();
 }
 void begin(){token=CancelToken();state=SessionState();update(Phase.preparing);}
 Future<File> prepare(File f,String pass)async{
  final source=f.path,target='${work.path}/${DateTime.now().microsecondsSinceEpoch}.vdp';
  final result=await Isolate.run(()=>Vault.seal(File(source),File(target),pass,CancelToken()));
  if(token.cancelled){if(await result.exists())await result.delete();token.check();}return result;
 }
 Future<File> accept(File encrypted,String pass,Channel channel)async{
  update(Phase.verifying);final source=encrypted.path,dest=received.path;
  final result=await Isolate.run(()=>Vault.open(File(source),Directory(dest),pass,CancelToken()));
  if(token.cancelled){await result.delete();token.check();}await record(result,channel,'received');update(Phase.completed,message:result.path);return result;
 }
 Future<void> record(File f,Channel c,String result)async{
  history.insert(0,{'name':f.uri.pathSegments.last,'path':result=='received'?f.path:null,'size':await f.length(),'channel':c.name,'result':result,'time':DateTime.now().toIso8601String()});
  if(history.length>200)history.removeRange(200,history.length);await(await SharedPreferences.getInstance()).setString('history',jsonEncode(history));notifyListeners();
 }
 Future<void> clearHistory()async{history.clear();await(await SharedPreferences.getInstance()).remove('history');notifyListeners();}
 void cancel(){token.cancelled=true;update(Phase.cancelled);}
}
