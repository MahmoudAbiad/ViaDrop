package app.viadrop.viadrop
import android.bluetooth.*
import android.content.Intent
import android.media.*
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.*
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
class MainActivity:FlutterActivity(){
 companion object{init{System.loadLibrary("viadrop_audio")}}
 private external fun waveInit():Long
 private external fun waveFree(h:Long)
 private external fun waveEncode(h:Long,data:ByteArray,high:Boolean):ByteArray?
 private external fun waveDecode(h:Long,data:ByteArray,n:Int):ByteArray?
 private val main=Handler(Looper.getMainLooper());private val workers=Executors.newCachedThreadPool()
 private var sink:EventChannel.EventSink?=null
 @Volatile private var listening=false
 @Volatile private var audioGeneration=0
 private var recorder:AudioRecord?=null;private var track:AudioTrack?=null
 @Volatile private var socket:BluetoothSocket?=null
 @Volatile private var server:BluetoothServerSocket?=null
 private val decision=ArrayBlockingQueue<Boolean>(1)
 private val service=UUID.fromString("4ec874f6-7276-44c2-8c72-e779ae6080b1")
 private val adapter:BluetoothAdapter? get()=getSystemService(BluetoothManager::class.java)?.adapter
 private fun emit(m:Map<String,Any>){main.post{sink?.success(m)}}
 override fun configureFlutterEngine(engine:FlutterEngine){
  super.configureFlutterEngine(engine)
  EventChannel(engine.dartExecutor.binaryMessenger,"app.viadrop/events").setStreamHandler(object:EventChannel.StreamHandler{
   override fun onListen(arguments:Any?,events:EventChannel.EventSink){sink=events}
   override fun onCancel(arguments:Any?){sink=null}
  })
  MethodChannel(engine.dartExecutor.binaryMessenger,"app.viadrop/native").setMethodCallHandler{call,result->
   fun done(v:Any?=null){main.post{result.success(v)}}
   fun fail(e:Exception){main.post{result.error("NATIVE",e.message,null)}}
   when(call.method){
    "btAvailable"->try{done(adapter?.isEnabled==true)}catch(e:Exception){fail(e)}
    "btPeers"->try{done(adapter?.bondedDevices?.map{mapOf("address" to it.address,"name" to(it.name?:it.address))}?:emptyList<Any>())}catch(e:Exception){fail(e)}
    "btSettings"->{startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS));done()}
    "btAccept"->{decision.offer(call.argument<Boolean>("accept")==true);done()}
    "btStop"->{stopBluetooth();done()}
    "btListen"->workers.execute{try{listenBluetooth();done()}catch(e:Exception){fail(e)}}
    "btSend"->workers.execute{try{sendBluetooth(call.argument<String>("address")!!,call.argument<String>("path")!!);done()}catch(e:Exception){fail(e)}}
    "audioListen"->try{listenAudio();done()}catch(e:Exception){fail(e)}
    "audioStop"->{stopAudio();done()}
    "audioPlay"->workers.execute{try{playAudio(call.argument<ByteArray>("data")!!,call.argument<Boolean>("high")==true);done()}catch(e:Exception){fail(e)}}
    "sharedFiles"->workers.execute{try{done(importShared(intent));intent=Intent()}catch(e:Exception){fail(e)}}
    else->result.notImplemented()
   }
  }
 }
 private fun playAudio(data:ByteArray,high:Boolean){
  val generation=audioGeneration;val h=waveInit();if(h<0)throw IOException("Audio initialization failed")
  try{
   val pcm=waveEncode(h,data,high)?:throw IOException("Encoding failed");if(generation!=audioGeneration)return
   val min=AudioTrack.getMinBufferSize(48000,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_16BIT)
   val player=AudioTrack.Builder().setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()).setAudioFormat(AudioFormat.Builder().setSampleRate(48000).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()).setBufferSizeInBytes(maxOf(min,8192)).setTransferMode(AudioTrack.MODE_STREAM).build()
   track=player
   try{player.play();var offset=0;while(offset<pcm.size&&generation==audioGeneration){val n=player.write(pcm,offset,minOf(4096,pcm.size-offset));if(n<=0)throw IOException("Audio output failed");offset+=n};while(generation==audioGeneration&&player.playbackHeadPosition<pcm.size/2){Thread.sleep(20)}}
   finally{try{player.stop()}catch(_:Exception){};player.release();if(track===player)track=null}
  }finally{waveFree(h)}
 }
 private fun listenAudio(){
  if(listening)return
  val min=AudioRecord.getMinBufferSize(48000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT)
  val r=AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION,48000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT,maxOf(min,8192))
  if(r.state!=AudioRecord.STATE_INITIALIZED){r.release();throw IOException("Microphone unavailable")};recorder=r;listening=true;r.startRecording()
  workers.execute{val h=waveInit();try{if(h<0)throw IOException("Decoder unavailable");val b=ByteArray(2048);while(listening){val n=r.read(b,0,b.size);if(n<0)throw IOException("Microphone read failed");if(n>0){waveDecode(h,b,n)?.let{emit(mapOf("type" to "audioData","data" to it))}}}}
   catch(e:Exception){if(listening)emit(mapOf("type" to "error","message" to(e.message?:"Audio error")))}
   finally{if(h>=0)waveFree(h);try{r.stop()}catch(_:Exception){};r.release();if(recorder===r)recorder=null}}
 }
 private fun stopAudio(){audioGeneration++;listening=false;try{recorder?.stop()}catch(_:Exception){};try{track?.pause()}catch(_:Exception){}}
 private fun sendBluetooth(address:String,path:String){
  val a=adapter?:throw IOException("Bluetooth unavailable");val device=a.getRemoteDevice(address)
  if(device.bondState!=BluetoothDevice.BOND_BONDED)throw IOException("Pair in Android settings first")
  a.cancelDiscovery();val s=device.createRfcommSocketToServiceRecord(service);socket=s
  try{
   s.connect();val out=DataOutputStream(s.outputStream);val input=DataInputStream(s.inputStream);val file=File(path);val length=file.length();if(length>1074790400L)throw IOException("Size limit")
   out.writeInt(0x56444231);out.writeLong(length);out.flush();if(input.read()!=1)throw IOException("Receiver declined")
   file.inputStream().use{f->val b=ByteArray(65536);var sent=0L;while(true){val n=f.read(b);if(n<0)break;out.write(b,0,n);sent+=n;emit(mapOf("type" to "btProgress","done" to sent,"total" to length))}};out.flush();if(input.read()!=2)throw IOException("Receiver verification failed")
  }finally{s.close();if(socket===s)socket=null}
 }
 private fun listenBluetooth(){
  if(server!=null)return;val ss=adapter?.listenUsingRfcommWithServiceRecord("ViaDrop",service)?:throw IOException("Bluetooth unavailable");server=ss
  workers.execute{try{while(server===ss){val s=ss.accept();socket=s;var file:File?=null
   try{
    if(s.remoteDevice.bondState!=BluetoothDevice.BOND_BONDED)throw IOException("Unpaired peer")
    val input=DataInputStream(s.inputStream);val out=s.outputStream;if(input.readInt()!=0x56444231)throw IOException("Invalid header")
    val length=input.readLong();if(length<0||length>1074790400L)throw IOException("Size limit")
    decision.clear();emit(mapOf("type" to "btOffer","name" to(s.remoteDevice.name?:s.remoteDevice.address),"size" to length))
    if(decision.poll(60,TimeUnit.SECONDS)!=true){out.write(0);continue};out.write(1);out.flush();file=File.createTempFile("bt-",".vdp",cacheDir)
    file.outputStream().use{f->val b=ByteArray(65536);var done=0L;while(done<length){val n=input.read(b,0,minOf(b.size.toLong(),length-done).toInt());if(n<=0)throw EOFException();f.write(b,0,n);done+=n;emit(mapOf("type" to "btProgress","done" to done,"total" to length))}}
    decision.clear();emit(mapOf("type" to "btFile","path" to file.absolutePath));out.write(if(decision.poll(180,TimeUnit.SECONDS)==true)2 else 0);out.flush()
   }catch(e:Exception){if(server===ss)emit(mapOf("type" to "error","message" to(e.message?:"Bluetooth error")))}finally{file?.delete();s.close();if(socket===s)socket=null}
  }}catch(e:Exception){if(server===ss)emit(mapOf("type" to "error","message" to(e.message?:"Bluetooth stopped")))}}
 }
 private fun stopBluetooth(){val ss=server;server=null;try{ss?.close()}catch(_:Exception){};try{socket?.close()}catch(_:Exception){};socket=null;decision.offer(false)}
 private fun importShared(i:Intent?):List<String>{
  if(i==null)return emptyList();val result=mutableListOf<String>()
  if(i.action==Intent.ACTION_SEND&&i.type=="text/plain"){i.getStringExtra(Intent.EXTRA_TEXT)?.let{val f=File.createTempFile("shared-",".txt",cacheDir);f.writeText(it);result.add(f.path)}}
  else if(i.action==Intent.ACTION_SEND||i.action==Intent.ACTION_SEND_MULTIPLE){
   val uris=if(i.action==Intent.ACTION_SEND_MULTIPLE)i.getParcelableArrayListExtra<android.net.Uri>(Intent.EXTRA_STREAM)?:arrayListOf() else arrayListOf<android.net.Uri>().apply{i.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)?.let{add(it)}}
   for(uri in uris.take(30)){val f=File.createTempFile("shared-",".bin",cacheDir);try{val input=contentResolver.openInputStream(uri)?:throw IOException("Cannot open content");input.use{source->f.outputStream().use{out->val b=ByteArray(65536);var total=0L;while(true){val n=source.read(b);if(n<0)break;total+=n;if(total>1073741824L)throw IOException("Size limit");out.write(b,0,n)}}};result.add(f.path)}catch(e:Exception){f.delete();throw e}}
  };return result
 }
 override fun onNewIntent(intent:Intent){super.onNewIntent(intent);setIntent(intent);emit(mapOf("type" to "shared"))}
 override fun onDestroy(){stopAudio();stopBluetooth();workers.shutdownNow();super.onDestroy()}
}
