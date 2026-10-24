import 'dart:async';
import 'dart:io';
enum Channel {wifi,bluetooth,qr,audio}
enum Phase {idle,preparing,discovering,waiting,transferring,verifying,completed,cancelled,failed}
class Capabilities {
 const Capabilities({this.discovery=false,this.pause=false,this.resume=false,this.maxBytes=1024*1024*1024});
 final bool discovery,pause,resume;final int maxBytes;
}
class Peer {const Peer(this.id,this.name);final String id,name;}
class CancelToken {bool cancelled=false;void check(){if(cancelled)throw const TransferCancelled();}}
class TransferCancelled implements Exception {const TransferCancelled();}
class TransferStatus {
 const TransferStatus(this.phase,{this.done=0,this.total=0,this.message=''});
 final Phase phase;final int done,total;final String message;
 double get progress=>total==0?0:(done/total).clamp(0,1);
}
abstract class TransferEngine {
 Channel get channel;Capabilities get capabilities;
 Future<bool> checkAvailability();Future<void> initialize();Stream<Peer> discover();
 Future<void> send(File sealed,Peer? peer,CancelToken token,void Function(int,int) progress);
 Future<void> receive();Future<void> cancel();Future<void> dispose();
 Future<void> pause()=>Future.error(UnsupportedError('Pause unavailable'));
 Future<void> resume()=>Future.error(UnsupportedError('Resume unavailable'));
}
class SessionState {
 Phase phase=Phase.idle;
 void transition(Phase next){
  if(next==phase)return;
  const allowed={
   Phase.idle:[Phase.preparing,Phase.discovering,Phase.waiting,Phase.failed],
   Phase.preparing:[Phase.discovering,Phase.waiting,Phase.transferring,Phase.failed,Phase.cancelled],
   Phase.discovering:[Phase.preparing,Phase.waiting,Phase.failed,Phase.cancelled],
   Phase.waiting:[Phase.transferring,Phase.verifying,Phase.failed,Phase.cancelled],
   Phase.transferring:[Phase.preparing,Phase.verifying,Phase.completed,Phase.failed,Phase.cancelled],
   Phase.verifying:[Phase.completed,Phase.failed,Phase.cancelled],
   Phase.completed:[Phase.idle,Phase.preparing,Phase.transferring,Phase.verifying,Phase.cancelled,Phase.failed],
   Phase.failed:[Phase.idle,Phase.preparing,Phase.cancelled],Phase.cancelled:[Phase.idle,Phase.preparing]
  };
  if(!allowed[phase]!.contains(next))throw StateError('$phase → $next');phase=next;
 }
}
Channel recommend(int bytes,Set<Channel> available){
 for(final c in [Channel.wifi,Channel.bluetooth,if(bytes<=2048)Channel.audio,Channel.qr]){
  if(available.contains(c)&&(c!=Channel.qr||bytes<=512*1024))return c;
 }throw StateError('No suitable channel available');
}
String safeName(String name){
 var n=name.replaceAll(RegExp(r'[\\/\x00-\x1f\x7f:*?"<>|]'),'_').trim().replaceAll(RegExp(r'^\.+'),'');
 if(n.isEmpty)n='received.bin';return n.runes.take(120).map(String.fromCharCode).join();
}
