package app.viadrop.viadrop
import android.bluetooth.*
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
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
 private var colorBridge:ColorBridge?=null
 private var audioBridge:AudioBridge?=null
 companion object{init{System.loadLibrary("viadrop_audio")}}
 private external fun waveInit():Long
 private external fun waveFree(h:Long)
 private external fun waveEncode(h:Long,data:ByteArray,high:Boolean):ByteArray?
 private external fun waveDecode(h:Long,data:ByteArray,n:Int):ByteArray?
 private external fun ofdmInit():Long
 private external fun ofdmFree(h:Long)
 private external fun ofdmEncode(data:ByteArray):ByteArray?
 private external fun ofdmDecode(h:Long,data:ByteArray):ByteArray?
 private val main=Handler(Looper.getMainLooper());private val workers=Executors.newCachedThreadPool()
 private var sink:EventChannel.EventSink?=null
 @Volatile private var socket:BluetoothSocket?=null
 @Volatile private var server:BluetoothServerSocket?=null
 private val decision=ArrayBlockingQueue<Boolean>(1)
 private val service=UUID.fromString("4ec874f6-7276-44c2-8c72-e779ae6080b1")
 private val adapter:BluetoothAdapter? get()=getSystemService(BluetoothManager::class.java)?.adapter
 private fun emit(m:Map<String,Any>){main.post{sink?.success(m)}}
 override fun configureFlutterEngine(engine:FlutterEngine){
  super.configureFlutterEngine(engine)
  colorBridge=ColorBridge(this,engine)
  audioBridge=AudioBridge(this,engine,object:AudioCodec{
   override fun waveInit()=this@MainActivity.waveInit()
   override fun waveFree(handle:Long)=this@MainActivity.waveFree(handle)
   override fun waveEncode(handle:Long,data:ByteArray,high:Boolean)=this@MainActivity.waveEncode(handle,data,high)
   override fun waveDecode(handle:Long,data:ByteArray,count:Int)=this@MainActivity.waveDecode(handle,data,count)
   override fun ofdmInit()=this@MainActivity.ofdmInit()
   override fun ofdmFree(handle:Long)=this@MainActivity.ofdmFree(handle)
   override fun ofdmEncode(data:ByteArray)=this@MainActivity.ofdmEncode(data)
   override fun ofdmDecode(handle:Long,data:ByteArray)=this@MainActivity.ofdmDecode(handle,data)
  })
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
    "physicalCapabilities"->workers.execute{
     try{done(probePhysicalCapabilities())}catch(e:Exception){fail(e)}
    }
    "sharedFiles"->workers.execute{try{done(importShared(intent));intent=Intent()}catch(e:Exception){fail(e)}}
    else->result.notImplemented()
   }
  }
 }
 // Checks platform capabilities without requesting microphone/camera permission.
 // These values are candidate hints, NOT a speaker-to-mic link benchmark.
 private fun probePhysicalCapabilities():Map<String,Any>{
  val camera=packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
  val microphone=packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)
  var cameraMaxFps=0
  if(camera){
   try{
    val cm=getSystemService(Context.CAMERA_SERVICE) as CameraManager
    for(id in cm.cameraIdList){
     val c=cm.getCameraCharacteristics(id)
     val facing=c.get(CameraCharacteristics.LENS_FACING)
     if(facing!=CameraCharacteristics.LENS_FACING_BACK)continue
     val ranges=c.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
     if(ranges!=null)for(range in ranges){
      cameraMaxFps=maxOf(cameraMaxFps,range.upper)
     }
    }
   }catch(_:Exception){}
  }
  val displayHz=try{windowManager.defaultDisplay.refreshRate.toDouble()}catch(_:Exception){0.0}
  val pcmInput=try{AudioRecord.getMinBufferSize(48000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT)>0}catch(_:Exception){false}
  val pcmOutput=try{AudioTrack.getMinBufferSize(48000,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_16BIT)>0}catch(_:Exception){false}
  val audioManager=getSystemService(Context.AUDIO_SERVICE) as AudioManager
  val ultrasoundInput=try{audioManager.getProperty("android.media.property.SUPPORT_MIC_NEAR_ULTRASOUND")=="true"}catch(_:Exception){false}
  val ultrasoundOutput=try{audioManager.getProperty("android.media.property.SUPPORT_SPEAKER_NEAR_ULTRASOUND")=="true"}catch(_:Exception){false}
  var ofdmNative=false
  var h=0L
  try{
   h=ofdmInit()
   ofdmNative=h!=0L
  }catch(_:Throwable){
   ofdmNative=false
  }finally{
   if(h!=0L)try{ofdmFree(h)}catch(_:Throwable){}
  }
  return mapOf(
   "probeOk" to true,"camera" to camera,"cameraMaxFps" to cameraMaxFps,
   "displayHz" to displayHz,
   "displayWidthPx" to resources.displayMetrics.widthPixels,
   "microphone" to microphone,
   "audioInput48k" to pcmInput,"audioOutput48k" to pcmOutput,
   "ofdmNative" to ofdmNative,
   "androidSdk" to android.os.Build.VERSION.SDK_INT,
   "processorCores" to Runtime.getRuntime().availableProcessors(),
   "ultrasoundInput" to ultrasoundInput,
   "ultrasoundOutput" to ultrasoundOutput
  )
 }
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
 override fun onPause(){audioBridge?.stop(null);colorBridge?.stop(null);super.onPause()}
 override fun onDestroy(){audioBridge?.dispose();colorBridge?.dispose();stopBluetooth();workers.shutdownNow();super.onDestroy()}
}
