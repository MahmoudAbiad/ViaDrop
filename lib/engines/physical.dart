import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../core/transfer.dart';
import '../core/vault.dart';
import '../third_party/onesend/fountain.dart';
import '../third_party/onesend/protocol.dart';
import 'qr_codec.dart';
class PhysicalDecoder {
 PhysicalDecoder(this.maxBytes,{this.expectedSessionId});final int maxBytes;final int? expectedSessionId;FrameHeader? header;LTDecoder? decoder;
 double get progress=>decoder==null?0:decoder!.solvedCount/decoder!.blockCount;
 Uint8List? add(Uint8List bytes){
  if(bytes.length>1100)return null;final p=parseFrame(bytes);if(p==null)return null;final h=p.header;
  if(h.protocolVersion!=2||h.totalLength>maxBytes||h.blockLength>1024||h.blockCount>20000||
     (expectedSessionId!=null&&h.sessionId!=expectedSessionId))return null;
  if(header!=null&&!header!.matches(h))return null;header??=h;
  decoder??=LTDecoder(blockCount:h.blockCount,blockLength:h.blockLength,sessionId:h.sessionId,totalLength:h.totalLength);
  decoder!.addFrame(h.sequence,p.block);final result=decoder!.assemble();
  if(result!=null&&crc32(result)!=h.payloadChecksum){
   // A fully assembled but invalid transfer must not lock the receiver onto
   // its session forever. Discard all its frames before the next transmission.
   header=null;decoder=null;
   throw const FormatException('Payload checksum failed');
  }
  return result;
 }
}
/// Consume every QR code reported in one camera capture. The scanner may
/// report multiple codes at once, and a single fountain frame rarely finishes
/// a transfer. Invalid or unrelated QR strings must not block valid frames.
Uint8List? decodeQrCapture(PhysicalDecoder decoder, Iterable<String?> rawValues) {
 for(final text in rawValues) {
  if(text==null)continue;
  final packet=decodeQrFrame(text);
  if(packet==null)continue;
  final complete=decoder.add(packet);
  if(complete!=null)return complete;
 }
 return null;
}
class PhysicalEngine extends TransferEngine {
 PhysicalEngine(this.channel,{required this.emit,this.startListening,this.stopListening,this.sessionId});
 @override final Channel channel;final int? sessionId;final Future<void> Function(Uint8List) emit;final Future<void> Function()? startListening,stopListening;
 int fps=6,blockLength=300,audioBlockLength=100;bool paused=false;CancelToken? _token;
 @override Capabilities get capabilities=>Capabilities(pause:true,resume:true,maxBytes:channel==Channel.audio?64*1024:512*1024);
 @override Future<bool> checkAvailability()async=>true;
 @override Future<void> initialize()async{}
 @override Stream<Peer> discover()=>const Stream.empty();
 @override Future<void> receive()async{await startListening?.call();}
 @override Future<void> send(File sealed,Peer? peer,CancelToken token,void Function(int,int) progress)async{
  _token=token;token.check();if(await sealed.length()>capabilities.maxBytes)throw StateError('Size limit exceeded');
  final payload=await sealed.readAsBytes();final id=sessionId??(ByteData.sublistView(Vault.random(4)).getUint32(0)|1);final length=channel==Channel.audio?audioBlockLength:blockLength;
  final enc=LTEncoder(payload:payload,blockLength:length,sessionId:id);final checksum=crc32(payload);var seq=0;
  while(!token.cancelled){
   if(paused){await Future<void>.delayed(const Duration(milliseconds:100));continue;}
   await emit(packFrame(FrameHeader(sessionId:id,sequence:seq,blockCount:enc.blockCount,blockLength:length,totalLength:payload.length,payloadChecksum:checksum),enc.encode(seq)));
   progress(++seq,enc.blockCount);await Future<void>.delayed(Duration(milliseconds:channel==Channel.audio?180:1000~/fps));
  }token.check();
 }
 @override Future<void> pause()async{paused=true;}
 @override Future<void> resume()async{paused=false;}
 @override Future<void> cancel()async{_token?.cancelled=true;await stopListening?.call();}
 @override Future<void> dispose()=>cancel();
}
