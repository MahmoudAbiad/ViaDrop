import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/core/transfer.dart';
import 'package:viadrop/core/vault.dart';
import 'package:viadrop/engines/lan.dart';

void main(){
 late Directory temp;LanEngine? receiver,sender;
 setUp(()async{temp=await Directory.systemTemp.createTemp('viadrop-radio-');});
 tearDown(()async{await sender?.dispose();await receiver?.dispose();sender=null;receiver=null;await temp.delete(recursive:true);});
 Future<Peer?> start({required Future<bool> Function(String,int) consent,required Future<void> Function(File) accept,void Function(Object)? error})async{
  final ips=(await NetworkInterface.list(type:InternetAddressType.IPv4)).expand((i)=>i.addresses).where(isPrivateLanAddress);
  if(ips.isEmpty){markTestSkipped('No private IPv4 interface: host integration cannot run');return null;}
  final tcp=await ServerSocket.bind(InternetAddress.anyIPv4,0);final port=tcp.port;await tcp.close();
  final udp=await RawDatagramSocket.bind(InternetAddress.anyIPv4,0);final discovery=udp.port;udp.close();
  receiver=LanEngine(directory:temp,port:port,discoveryPort:discovery,consent:consent,onFile:accept,onProgress:(_,__){},onError:error??(_){});
  sender=LanEngine(directory:temp,port:port,discoveryPort:discovery,consent:(_,__)async=>false,onFile:(_)async{},onProgress:(_,__){},onError:(_){});
  await receiver!.initialize();return Peer(ips.first.address,'host receiver');
 }
 test('receiver refusal never uploads or saves a file',()async{
  var saved=false;final peer=await start(consent:(_,__)async=>false,accept:(_)async{saved=true;});if(peer==null)return;
  final file=await File('${temp.path}/sealed.vdp').writeAsBytes([1,2,3]);
  await expectLater(sender!.send(file,peer,CancelToken(),(_,__){}),throwsStateError);
  expect(saved,false);expect(await temp.list().where((f)=>f.path.contains('/lan-')).length,0);
 });
 test('wrong passphrase fails receiver verification and sender success',()async{
  final errors=<Object>[];
  final peer=await start(consent:(_,__)async=>true,accept:(f)async{await Vault.open(f,Directory('${temp.path}/received'),'wrong-password-12345',CancelToken());},error:errors.add);if(peer==null)return;
  final original=await File('${temp.path}/عربي.txt').writeAsString('نص عربي مطابق');
  final file=await Vault.seal(original,File('${temp.path}/sealed.vdp'),'correct-password-12345',CancelToken());
  await expectLater(sender!.send(file,peer,CancelToken(),(_,__){}),throwsStateError);
  expect(errors,isNotEmpty);expect(await temp.list().where((f)=>f.path.contains('/lan-')).length,0);
 });
 test('empty user file roundtrips through encrypted streaming LAN',()async{
  File? restored;
  final peer=await start(consent:(_,__)async=>true,accept:(f)async{restored=await Vault.open(f,Directory('${temp.path}/received'),'shared-password-12345',CancelToken());});if(peer==null)return;
  final original=await File('${temp.path}/فارغ.bin').writeAsBytes([]);
  final file=await Vault.seal(original,File('${temp.path}/sealed.vdp'),'shared-password-12345',CancelToken());
  await sender!.send(file,peer,CancelToken(),(_,__){});
  expect(await restored!.length(),0);expect(restored!.uri.pathSegments.last,contains('فارغ'));
 });
 test('cancel interrupts waiting consent and invalidates its late approval',()async{
  final offered=Completer<void>(),decision=Completer<bool>();var saved=false;
  final peer=await start(consent:(_,__)async{offered.complete();return decision.future;},accept:(_)async{saved=true;});if(peer==null)return;
  final file=await File('${temp.path}/sealed.vdp').writeAsBytes([1,2,3]);
  final sending=sender!.send(file,peer,CancelToken(),(_,__){});
  final result=expectLater(sending,throwsA(anything));await offered.future;
  await receiver!.cancel();decision.complete(true);await result;expect(saved,false);
 });
 test('sender rejects public destination before touching source file',()async{
  sender=LanEngine(directory:temp,consent:(_,__)async=>false,onFile:(_)async{},onProgress:(_,__){},onError:(_){});
  await expectLater(sender!.send(File('missing'),const Peer('8.8.8.8','public'),CancelToken(),(_,__){}),throwsArgumentError);
 });
}
