import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'transfer.dart';
class Vault {
 static const block=65536;
 static final cipher=AesGcm.with256bits();
 static Uint8List random(int n){final r=Random.secure();return Uint8List.fromList(List.generate(n,(_)=>r.nextInt(256)));}
 static Future<SecretKey> key(String pass,List<int> salt){
  if(pass.length<12)throw ArgumentError('Use a shared passphrase of at least 12 characters');
  return Pbkdf2(macAlgorithm:Hmac.sha256(),iterations:210000,bits:256).deriveKey(secretKey:SecretKey(utf8.encode(pass)),nonce:salt);
 }
 static Uint8List u32(int n)=>(ByteData(4)..setUint32(0,n)).buffer.asUint8List();
 static Future<Uint8List> exact(RandomAccessFile f,int n)async{
  final b=Uint8List(n);var p=0;while(p<n){final r=await f.readInto(b,p,n);if(r==0)throw const FormatException('Truncated transfer');p+=r;}return b;
 }
 static Future<File> seal(File input,File output,String pass,CancelToken token)async{
  final salt=random(16),header=Uint8List.fromList([86,68,80,49,...salt]);
  final k=await key(pass,salt);token.check();
  final digest=await hashes.sha256.bind(input.openRead()).first;final size=await input.length();
  final out=await output.open(mode:FileMode.write),src=await input.open();var index=0;
  Future<void> record(List<int> bytes)async{
   token.check();final nonce=random(12);final box=await cipher.encrypt(bytes,secretKey:k,nonce:nonce,aad:[...header,...u32(index++)]);
   final b=[...nonce,...box.cipherText,...box.mac.bytes];await out.writeFrom(u32(b.length));await out.writeFrom(b);
  }
  try{
   await out.writeFrom(header);await record(utf8.encode(jsonEncode({'name':safeName(input.uri.pathSegments.last),'size':size,'sha256':digest.toString()})));
   while(true){final b=await src.read(block);if(b.isEmpty)break;await record(b);}
   await record(utf8.encode('END:$size:$digest'));await out.flush();return output;
  }catch(_){await out.close();if(await output.exists())await output.delete();rethrow;}
  finally{await src.close();try{await out.close();}catch(_){}}
 }
 static Future<File> open(File input,Directory destination,String pass,CancelToken token)async{
  final src=await input.open();RandomAccessFile? out;File? temp;
  try{
   final header=await exact(src,20);if(utf8.decode(header.sublist(0,4))!='VDP1')throw const FormatException('Unsupported envelope');
   final k=await key(pass,header.sublist(4));var index=0;
   Future<List<int>> record()async{
    token.check();final len=ByteData.sublistView(await exact(src,4)).getUint32(0);
    if(len<28||len>block+28)throw const FormatException('Invalid record size');final b=await exact(src,len);
    return cipher.decrypt(SecretBox(b.sublist(12,len-16),nonce:b.sublist(0,12),mac:Mac(b.sublist(len-16))),secretKey:k,aad:[...header,...u32(index++)]);
   }
   final meta=jsonDecode(utf8.decode(await record())) as Map<String,dynamic>;final size=meta['size'] as int,digest=meta['sha256'] as String;
   if(size<0||size>1024*1024*1024||!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest))throw const FormatException('Invalid metadata');
   await destination.create(recursive:true);temp=File('${destination.path}/.${base64Url.encode(random(12))}.partial');out=await temp.open(mode:FileMode.write);var done=0;
   while(done<size){final b=await record();if(b.isEmpty||done+b.length>size)throw const FormatException('Invalid length');await out.writeFrom(b);done+=b.length;}
   if(utf8.decode(await record())!='END:$size:$digest'||await src.position()!=await src.length())throw const FormatException('Invalid terminator');
   await out.close();out=null;if((await hashes.sha256.bind(temp.openRead()).first).toString()!=digest)throw const FormatException('Integrity check failed');token.check();
   final name=safeName(meta['name'] as String);return await temp.rename('${destination.path}/${DateTime.now().microsecondsSinceEpoch}-${base64Url.encode(random(4))}-$name');
  }finally{await src.close();await out?.close();if(temp!=null&&await temp.exists())await temp.delete();}
 }
}
