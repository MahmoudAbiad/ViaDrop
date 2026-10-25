import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../core/transfer.dart';
import '../core/vault.dart';
import '../third_party/onesend/fountain.dart';
import '../third_party/onesend/protocol.dart';
import 'qr_codec.dart';
class PhysicalDecoder {
 PhysicalDecoder(this.maxBytes,{this.expectedSessionId});
 final int maxBytes;
 final int? expectedSessionId;
 FrameHeader? header;
 LTDecoder? decoder;

 /// Counts packets seen by the decoder, not missing air/camera frames.
 int validFrames = 0;
 int rejectedFrames = 0;
 int completedBytes = 0;
 final Stopwatch _rxClock = Stopwatch();

 double get progress=>decoder==null?0:decoder!.solvedCount/decoder!.blockCount;
 double get receivedFramesPerSecond => _rxClock.elapsedMilliseconds == 0
     ? 0 : validFrames * 1000 / _rxClock.elapsedMilliseconds;
 /// Payload goodput from first accepted frame to complete reconstruction.
 /// Excludes setup, QR scanning of start packet and file decryption.
 double get payloadKiBPerSecond =>
     _rxClock.elapsedMilliseconds == 0 || completedBytes == 0
         ? 0 : completedBytes * 1000 / (_rxClock.elapsedMilliseconds * 1024);

 Uint8List? add(Uint8List bytes) {
  // QR-v40 optical frames carry up to 2400 block bytes plus 32 bytes
  // framing. Keep a strict input bound before doing CRC/fountain work.
  if(bytes.length>2600) {rejectedFrames++;return null;}
  final p=parseFrame(bytes);
  if(p==null) {rejectedFrames++;return null;}
  final h=p.header;
  if(h.protocolVersion!=2||h.totalLength>maxBytes||
     h.blockLength>2400||h.blockCount>20000||
     (expectedSessionId!=null&&h.sessionId!=expectedSessionId)) {
    rejectedFrames++;
    return null;
  }
  if(header!=null&&!header!.matches(h)) {
    rejectedFrames++;
    return null;
  }
  header??=h;
  decoder??=LTDecoder(
    blockCount:h.blockCount,blockLength:h.blockLength,
    sessionId:h.sessionId,totalLength:h.totalLength,
  );
  if(!_rxClock.isRunning&&completedBytes==0) _rxClock.start();
  validFrames++;
  decoder!.addFrame(h.sequence,p.block);
  final result=decoder!.assemble();
  if(result!=null&&crc32(result)!=h.payloadChecksum) {
   header=null;
   decoder=null;
   completedBytes=0;
   validFrames=0;
   _rxClock.stop();
   _rxClock.reset();
   rejectedFrames++;
   throw const FormatException('Payload checksum failed');
  }
  if(result!=null&&completedBytes==0) {
    completedBytes=result.length;
    _rxClock.stop();
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
 PhysicalEngine(this.channel,{required this.emit,this.startListening,this.stopListening,this.sessionId,this.emitBatch});
 @override final Channel channel;final int? sessionId;final Future<void> Function(Uint8List) emit;final Future<void> Function()? startListening,stopListening;
 final Future<void> Function(List<Uint8List>)? emitBatch;
 int qrTiles=1;
 int fps=6,blockLength=300,audioBlockLength=100,audioFrameGapMs=180;bool paused=false;CancelToken? _token;
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
   final tiles=channel==Channel.qr?qrTiles:1;
   if(tiles!=1&&tiles!=4)throw ArgumentError('Unsupported QR tile count');
   if(tiles>1&&emitBatch==null)throw StateError('Batch display unavailable');
   final packets=<Uint8List>[];
   for(var tile=0;tile<tiles;tile++){
    token.check();
    packets.add(packFrame(FrameHeader(sessionId:id,sequence:seq,blockCount:enc.blockCount,blockLength:length,totalLength:payload.length,payloadChecksum:checksum),enc.encode(seq)));
    seq++;
   }
   if(tiles>1){await emitBatch!(packets);}else{await emit(packets.single);}
   progress(seq,enc.blockCount);await Future<void>.delayed(Duration(milliseconds:channel==Channel.audio?audioFrameGapMs:1000~/fps));
  }token.check();
 }
 @override Future<void> pause()async{paused=true;}
 @override Future<void> resume()async{paused=false;}
 @override Future<void> cancel()async{_token?.cancelled=true;await stopListening?.call();}
 @override Future<void> dispose()=>cancel();
}
