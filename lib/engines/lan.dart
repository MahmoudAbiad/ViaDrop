import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/transfer.dart';
import '../core/vault.dart';
// ViaDrop LAN v1. Not LocalSend wire-compatible. Only encrypted VDP1 payloads.
/// Only accept local-network peers; never display or select our own address.
bool isPrivateLanAddress(InternetAddress address) {
 if(address.type != InternetAddressType.IPv4)return false;
 final octets=address.rawAddress;
 return octets[0]==10||
     (octets[0]==172&&octets[1]>=16&&octets[1]<=31)||
     (octets[0]==192&&octets[1]==168);
}

/// Reject malformed, foreign, public-address and self-originated broadcasts.
Peer? parseLanAnnouncement(List<int> bytes,InternetAddress sender,Set<String> localAddresses) {
 if(bytes.isEmpty||bytes.length>256||!isPrivateLanAddress(sender)||localAddresses.contains(sender.address))return null;
 try {
  final decoded=jsonDecode(utf8.decode(bytes));
  if(decoded is! Map||decoded['v']!='VD1')return null;
  return Peer(sender.address,'ViaDrop • ${sender.address}');
 } on FormatException {return null;}
}

class LanEngine extends TransferEngine {
 LanEngine({required this.directory,required this.consent,required this.onFile,required this.onProgress,required this.onError,this.port=47831,this.discoveryPort=47832});
 final Directory directory;final Future<bool> Function(String,int) consent;final Future<void> Function(File) onFile;final void Function(int,int) onProgress;final void Function(Object) onError;final int port,discoveryPort;
 int _epoch=0;bool _disposed=false;bool _sending=false;
 List<String> get localAddresses=>_localAddresses.where((v)=>isPrivateLanAddress(InternetAddress(v))).toList();
 HttpServer? _server;RawDatagramSocket? _udp;Timer? _timer;HttpClient? _client;bool _busy=false;Set<String> _localAddresses={};final _peers=StreamController<Peer>.broadcast();final _tickets=<String,({DateTime issued,int size,String remote})>{};
 @override Channel get channel=>Channel.wifi;
 @override Capabilities get capabilities=>const Capabilities(discovery:true);
 @override Future<bool> checkAvailability()async=>(await NetworkInterface.list(type:InternetAddressType.IPv4)).expand((i)=>i.addresses).any(isPrivateLanAddress);
 @override Future<void> initialize()async{
  if(_disposed)throw const TransferCancelled();
  if(_server!=null)return;
  final epoch=++_epoch;
  try{
   await _refreshLocalAddresses();
   if(epoch!=_epoch)throw const TransferCancelled();
   final server=await HttpServer.bind(InternetAddress.anyIPv4,port);
   if(epoch!=_epoch){await server.close(force:true);throw const TransferCancelled();}
   _server=server;server.idleTimeout=const Duration(seconds:20);
   _server!.listen((r)async{try{await _handle(r);}catch(e){if(epoch==_epoch)onError(e);try{r.response.statusCode=400;await r.response.close();}catch(_){}}});
   final socket=await RawDatagramSocket.bind(InternetAddress.anyIPv4,discoveryPort,reuseAddress:true);
   if(epoch!=_epoch){socket.close();throw const TransferCancelled();}
   _udp=socket;
   socket.broadcastEnabled=true;
   socket.listen((event){
    if(event!=RawSocketEvent.read)return;
    // Drain all queued datagrams so one busy peer cannot hide the next.
    while(true){
     final datagram=socket.receive();
     if(datagram==null)break;
     final peer=parseLanAnnouncement(datagram.data,datagram.address,_localAddresses);
     if(peer!=null&&!_peers.isClosed)_peers.add(peer);
    }
   },onError:onError);
   _timer=Timer.periodic(const Duration(seconds:2),(_)=>_broadcastDiscovery());
  }catch(_){
   // Binding the discovery socket can fail after the HTTP port is bound.
   // Always free every partially started resource so the user can retry.
   _timer?.cancel();_timer=null;
   _udp?.close();_udp=null;
   await _server?.close(force:true);_server=null;
   rethrow;
  }
 }
 Future<void> _refreshLocalAddresses()async{
  final interfaces=await NetworkInterface.list(type:InternetAddressType.IPv4);
  _localAddresses=interfaces.expand((network)=>network.addresses).map((ip)=>ip.address).toSet();
 }
 void _broadcastDiscovery(){
  final socket=_udp;
  if(socket==null)return;
  try{
   socket.send(utf8.encode('{"v":"VD1"}'),InternetAddress('255.255.255.255'),discoveryPort);
  }catch(error){onError(error);}
 }
 /// The Refresh button immediately announces our presence to nearby peers.
 Future<void> refreshDiscovery()async{
  await _refreshLocalAddresses();
  _broadcastDiscovery();
 }
 Future<void> _handle(HttpRequest r)async{
  final epoch=_epoch;
  Future<void> reject(int status)async{r.response.statusCode=status;await r.response.close();}
  final remoteAddress=r.connectionInfo?.remoteAddress;
  if(remoteAddress==null||!isPrivateLanAddress(remoteAddress)){await reject(403);return;}
  if(r.method!='POST'){await reject(405);return;}
  if(r.uri.path=='/offer'){
   if(_busy){await reject(409);return;}_busy=true;
   try{
    final bytes=<int>[];await for(final b in r.timeout(const Duration(seconds:10))){bytes.addAll(b);if(bytes.length>2048)throw const FormatException('Oversized offer');}
    final metadata=jsonDecode(utf8.decode(bytes));if(metadata is! Map||metadata['size'] is! int)throw const FormatException('Invalid offer');
    final size=metadata['size'] as int;if(size<0||size>capabilities.maxBytes+1024*1024)throw const FormatException('Size limit');
    final remote=r.connectionInfo!.remoteAddress.address;final ok=await consent('Wi-Fi • $remote',size).timeout(const Duration(seconds:60),onTimeout:()=>false);
    if(epoch!=_epoch)throw const TransferCancelled();
    if(!ok){await reject(403);}else{_tickets.clear();final t=base64Url.encode(Vault.random(24));_tickets[t]=(issued:DateTime.now(),size:size,remote:remote);r.response.write(t);await r.response.close();}
   }finally{_busy=false;}return;
  }
  if(r.uri.path=='/upload'){
   final ticket=_tickets.remove(r.headers.value('X-ViaDrop-Ticket'));
   if(_busy||ticket==null||DateTime.now().difference(ticket.issued).inSeconds>90||ticket.remote!=r.connectionInfo?.remoteAddress.address){await reject(403);return;}
   if(r.contentLength!=ticket.size){await reject(413);return;}_busy=true;
   final f=File('${directory.path}/lan-${base64Url.encode(Vault.random(12))}.vdp');final out=f.openWrite();var done=0;
   try{
    var reported=DateTime.now();
    await out.addStream(r.timeout(const Duration(seconds:30)).map((b){
     if(epoch!=_epoch)throw const TransferCancelled();
     done+=b.length;if(done>ticket.size)throw const FormatException('Length exceeded');
     final now=DateTime.now();if(done==ticket.size||now.difference(reported).inMilliseconds>=100){reported=now;onProgress(done,ticket.size);}
     return b;
    }));
    await out.close();if(epoch!=_epoch)throw const TransferCancelled();if(done!=ticket.size)throw const FormatException('Incomplete transfer');await onFile(f);await reject(200);
   }finally{await out.close();if(await f.exists())await f.delete();_busy=false;}return;
  }await reject(404);
 }
 @override Stream<Peer> discover()=>_peers.stream;
 @override Future<void> receive()=>initialize();
 @override Future<void> send(File sealed,Peer? peer,CancelToken token,void Function(int,int) progress)async{
  if(_disposed||token.cancelled)throw const TransferCancelled();
  if(_sending)throw StateError('A LAN send is already active');
  if(peer==null)throw ArgumentError('Select a peer');final a=InternetAddress.tryParse(peer.id);
  if(a==null||!isPrivateLanAddress(a))throw ArgumentError('Use a private LAN IPv4 address');
  _sending=true;final c=HttpClient()..connectionTimeout=const Duration(seconds:15);_client=c;
  try{
   final total=await sealed.length();if(total>capabilities.maxBytes+1024*1024)throw const FormatException('Size limit');token.check();final offer=await c.postUrl(Uri.parse('http://${peer.id}:$port/offer'));offer.followRedirects=false;offer.write(jsonEncode({'size':total}));
   final response=await offer.close().timeout(const Duration(seconds:70));if(response.statusCode!=200)throw StateError('Transfer declined (${response.statusCode})');
   final ticketBytes=<int>[];await for(final block in response.timeout(const Duration(seconds:10))){ticketBytes.addAll(block);if(ticketBytes.length>100)throw const FormatException('Invalid ticket');}
   final ticket=utf8.decode(ticketBytes);if(ticket.isEmpty)throw const FormatException('Missing ticket');token.check();
   final req=await c.postUrl(Uri.parse('http://${peer.id}:$port/upload'));req.followRedirects=false;req.contentLength=total;req.headers.set('X-ViaDrop-Ticket',ticket);var done=0;
   var reported=DateTime.now();
   await req.addStream(sealed.openRead().map((b){token.check();done+=b.length;final now=DateTime.now();if(done==total||now.difference(reported).inMilliseconds>=100){reported=now;progress(done,total);}return b;}));
   final result=await req.close().timeout(const Duration(minutes:3));await result.drain<void>();if(result.statusCode!=200)throw StateError('Receiver verification failed');
  }finally{c.close(force:true);if(identical(_client,c))_client=null;_sending=false;}
 }
 @override Future<void> cancel()async{++_epoch;_client?.close(force:true);await _server?.close(force:true);_server=null;_udp?.close();_udp=null;_timer?.cancel();_timer=null;_localAddresses.clear();_tickets.clear();}
 @override Future<void> dispose()async{if(_disposed)return;_disposed=true;await cancel();await _peers.close();}
}
