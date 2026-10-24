import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/transfer.dart';
import '../core/vault.dart';
// ViaDrop LAN v1. Not LocalSend wire-compatible. Only encrypted VDP1 payloads.
class LanEngine extends TransferEngine {
 LanEngine({required this.directory,required this.consent,required this.onFile,required this.onProgress,required this.onError,this.port=47831,this.discoveryPort=47832});
 final Directory directory;final Future<bool> Function(String,int) consent;final Future<void> Function(File) onFile;final void Function(int,int) onProgress;final void Function(Object) onError;final int port,discoveryPort;
 HttpServer? _server;RawDatagramSocket? _udp;Timer? _timer;HttpClient? _client;bool _busy=false;final _peers=StreamController<Peer>.broadcast();final _tickets=<String,({DateTime issued,int size,String remote})>{};
 @override Channel get channel=>Channel.wifi;
 @override Capabilities get capabilities=>const Capabilities(discovery:true);
 @override Future<bool> checkAvailability()async=>(await NetworkInterface.list(type:InternetAddressType.IPv4)).isNotEmpty;
 @override Future<void> initialize()async{
  if(_server!=null)return;
  try{
   _server=await HttpServer.bind(InternetAddress.anyIPv4,port);
   _server!.listen((r)async{try{await _handle(r);}catch(e){onError(e);try{r.response.statusCode=400;await r.response.close();}catch(_){}}});
   _udp=await RawDatagramSocket.bind(InternetAddress.anyIPv4,discoveryPort,reuseAddress:true);
   _udp!.broadcastEnabled=true;
   _udp!.listen((e){if(e!=RawSocketEvent.read)return;final d=_udp!.receive();if(d==null||d.data.length>256)return;try{if(jsonDecode(utf8.decode(d.data))['v']=='VD1')_peers.add(Peer(d.address.address,'ViaDrop • ${d.address.address}'));}catch(_){}});
   _timer=Timer.periodic(const Duration(seconds:2),(_){_udp?.send(utf8.encode('{"v":"VD1"}'),InternetAddress('255.255.255.255'),discoveryPort);});
  }catch(_){
   // Binding the discovery socket can fail after the HTTP port is bound.
   // Always free every partially started resource so the user can retry.
   _timer?.cancel();_timer=null;
   _udp?.close();_udp=null;
   await _server?.close(force:true);_server=null;
   rethrow;
  }
 }
 Future<void> _handle(HttpRequest r)async{
  Future<void> reject(int status)async{r.response.statusCode=status;await r.response.close();}
  if(r.method!='POST'){await reject(405);return;}
  if(r.uri.path=='/offer'){
   if(_busy){await reject(409);return;}_busy=true;
   try{
    final bytes=<int>[];await for(final b in r.timeout(const Duration(seconds:10))){bytes.addAll(b);if(bytes.length>2048)throw const FormatException('Oversized offer');}
    final size=jsonDecode(utf8.decode(bytes))['size'] as int;if(size<0||size>capabilities.maxBytes+1024*1024)throw const FormatException('Size limit');
    final remote=r.connectionInfo!.remoteAddress.address;final ok=await consent('Wi-Fi • $remote',size).timeout(const Duration(seconds:60),onTimeout:()=>false);
    if(!ok){await reject(403);}else{_tickets.clear();final t=base64Url.encode(Vault.random(24));_tickets[t]=(issued:DateTime.now(),size:size,remote:remote);r.response.write(t);await r.response.close();}
   }finally{_busy=false;}return;
  }
  if(r.uri.path=='/upload'){
   final ticket=_tickets.remove(r.headers.value('X-ViaDrop-Ticket'));
   if(_busy||ticket==null||DateTime.now().difference(ticket.issued).inSeconds>90||ticket.remote!=r.connectionInfo?.remoteAddress.address){await reject(403);return;}
   if(r.contentLength!=ticket.size){await reject(413);return;}_busy=true;
   final f=File('${directory.path}/lan-${base64Url.encode(Vault.random(12))}.vdp');final out=f.openWrite();var done=0;
   try{
    await for(final b in r.timeout(const Duration(seconds:30))){done+=b.length;if(done>ticket.size)throw const FormatException('Length exceeded');out.add(b);await out.flush();onProgress(done,ticket.size);}
    await out.close();if(done!=ticket.size)throw const FormatException('Incomplete transfer');await onFile(f);await reject(200);
   }finally{await out.close();if(await f.exists())await f.delete();_busy=false;}return;
  }await reject(404);
 }
 @override Stream<Peer> discover()=>_peers.stream;
 @override Future<void> receive()=>initialize();
 @override Future<void> send(File sealed,Peer? peer,CancelToken token,void Function(int,int) progress)async{
  if(peer==null)throw ArgumentError('Select a peer');final a=InternetAddress.tryParse(peer.id);
  if(a==null||a.type!=InternetAddressType.IPv4||!(peer.id.startsWith('192.168.')||peer.id.startsWith('10.')||(a.rawAddress[0]==172&&a.rawAddress[1]>=16&&a.rawAddress[1]<=31)))throw ArgumentError('Use a private LAN IPv4 address');
  final c=HttpClient()..connectionTimeout=const Duration(seconds:15);_client=c;
  try{
   final total=await sealed.length();final offer=await c.postUrl(Uri.parse('http://${peer.id}:$port/offer'));offer.followRedirects=false;offer.write(jsonEncode({'size':total}));
   final response=await offer.close().timeout(const Duration(seconds:70));if(response.statusCode!=200)throw StateError('Transfer declined (${response.statusCode})');
   final ticket=await response.transform(utf8.decoder).join();if(ticket.length>100)throw const FormatException('Invalid ticket');token.check();
   final req=await c.postUrl(Uri.parse('http://${peer.id}:$port/upload'));req.followRedirects=false;req.contentLength=total;req.headers.set('X-ViaDrop-Ticket',ticket);var done=0;
   await for(final b in sealed.openRead()){token.check();req.add(b);await req.flush();progress(done+=b.length,total);}
   final result=await req.close().timeout(const Duration(minutes:3));await result.drain<void>();if(result.statusCode!=200)throw StateError('Receiver verification failed');
  }finally{c.close(force:true);_client=null;}
 }
 @override Future<void> cancel()async{_client?.close(force:true);await _server?.close(force:true);_server=null;_udp?.close();_udp=null;_timer?.cancel();_tickets.clear();}
 @override Future<void> dispose()async{await cancel();await _peers.close();}
}
