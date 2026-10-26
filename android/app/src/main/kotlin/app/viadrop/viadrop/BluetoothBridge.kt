// Copyright 2026 Mahmoud Abiad. All rights reserved.
package app.viadrop.viadrop

import android.Manifest
import android.bluetooth.*
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.*
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Secure, bonded RFCOMM only. The wire carries VDP1 ciphertext, never keys.
 * One worker owns a session until finally closes it; stop replies wait for it.
 * No BLE fallback, network handoff, reflection, or insecure RFCOMM sockets.
 */
class BluetoothBridge(private val activity: FlutterActivity, engine: FlutterEngine) {
 private val main=Handler(Looper.getMainLooper())
 private val io=Executors.newSingleThreadExecutor()
 private val guard=Executors.newSingleThreadScheduledExecutor()
 private var sink:EventChannel.EventSink?=null
 private var active:Session?=null // main thread only
 private var disposed=false
 private var nextGeneration=0L
 private val ids=AtomicLong()
 private val service=UUID.fromString("4ec874f6-7276-44c2-8c72-e779ae6080b1")
 private val adapter:BluetoothAdapter? get()=activity.getSystemService(BluetoothManager::class.java)?.adapter
 private class Session(val client:Long,val generation:Long) {
  @Volatile var running=true
  @Volatile var socket:BluetoothSocket?=null
  @Volatile var server:BluetoothServerSocket?=null
  @Volatile var deadline=Long.MAX_VALUE
  @Volatile var error:String?=null
  @Volatile var decisionId=0L
  val decisions=ArrayBlockingQueue<Boolean>(1)
  val stops=mutableListOf<MethodChannel.Result>() // main only
  var result:MethodChannel.Result?=null // main only
 }
 init {
  EventChannel(engine.dartExecutor.binaryMessenger,"app.viadrop/bluetooth-events").setStreamHandler(object:EventChannel.StreamHandler {
   override fun onListen(arguments:Any?,events:EventChannel.EventSink){sink=events}
   override fun onCancel(arguments:Any?){sink=null;if(arguments==null)stopAll()}
  })
  MethodChannel(engine.dartExecutor.binaryMessenger,"app.viadrop/bluetooth").setMethodCallHandler { call,result ->
   try {
    val client=call.argument<Number>("clientId")?.toLong()?:0L
    when(call.method) {
     "info"->result.success(mapOf("sdk" to Build.VERSION.SDK_INT,"supported" to (adapter!=null)))
     "settings"->{activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS));result.success(null)}
     "peers"->{requirePermission();result.success(adapter?.bondedDevices?.map { mapOf("id" to it.address,"name" to (it.name?:it.address)) }?:emptyList<Any>())}
     "startSend","listen"->{
      requirePermission()
      check(!disposed&&active==null){"Bluetooth busy: wait for the previous session to stop"}
      check(client>0){"Invalid Bluetooth client"}
      check(adapter?.isEnabled==true){"Enable Bluetooth in Android settings"}
      val s=Session(client,++nextGeneration);active=s;s.result=result
      val address=call.argument<String>("address");val path=call.argument<String>("path")
      val listening=call.method=="listen"
      io.execute {
       val watchdog=guard.scheduleAtFixedRate({
        if(s.running&&System.nanoTime()>s.deadline){s.error="Bluetooth timed out";s.running=false;close(s)}
       },1,1,TimeUnit.SECONDS)
       var failure:Exception?=null
       try { if(listening)listen(s) else send(s,address?:throw IOException("Missing peer"),path?:throw IOException("Missing file")) }
       catch(e:Exception){failure=e}
       finally {
        close(s);watchdog.cancel(false)
        val error=failure
        main.post {
         if(active===s){
          if(error!=null&&s.running||s.error!=null)sink?.success(mapOf("type" to "stopped","message" to (s.error?:error?.message?:"Bluetooth stopped"),"clientId" to s.client,"generation" to s.generation))
          val pending=s.result;s.result=null
          if(pending!=null){
           if(!s.running)pending.error("BT_CANCELLED",s.error?:"Bluetooth cancelled",null)
           else if(error!=null)pending.error("BT_IO",error.message,null)
           else pending.success(mapOf("generation" to s.generation))
          }
          active=null
          val replies=s.stops.toList();s.stops.clear();for(reply in replies)try{reply.success(null)}catch(_:RuntimeException){}
          if(disposed){io.shutdown();guard.shutdown()}
         }
        }
       }
      }
     }
     "decision"->{
      val s=active;val id=call.argument<Number>("decisionId")?.toLong()
      if(s!=null&&s.running&&s.client==client&&id!=null&&id==s.decisionId){s.decisions.offer(call.argument<Boolean>("accept")==true)}
      result.success(null)
     }
     "stop"->{val s=active;if(s==null||s.client!=client)result.success(null) else stop(s,result)}
     else->result.notImplemented()
    }
   }catch(e:Exception){result.error("BT_STATE",e.message,null)}
  }
 }
 private fun requirePermission(){
  if(Build.VERSION.SDK_INT>=31)for(p in arrayOf(Manifest.permission.BLUETOOTH_CONNECT,Manifest.permission.BLUETOOTH_SCAN))
   if(activity.checkSelfPermission(p)!=PackageManager.PERMISSION_GRANTED)throw SecurityException("Bluetooth permission denied")
 }
 private fun checkRunning(s:Session){if(!s.running)throw IOException(s.error?:"Cancelled")}
 private fun deadline(s:Session,seconds:Long){s.deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(seconds)}
 private fun emit(s:Session,event:Map<String,Any>){
  main.post { if(active===s&&s.running)sink?.success(event+mapOf("clientId" to s.client,"generation" to s.generation)) }
 }
 private fun ready(s:Session){main.post {if(active===s&&s.running){val r=s.result;s.result=null;r?.success(mapOf("generation" to s.generation))}}}
 private fun decide(s:Session,type:String,extra:Map<String,Any>,seconds:Long):Boolean {
  s.decisions.clear();val id=ids.incrementAndGet();s.decisionId=id
  // The watchdog also closes the socket if Flutter goes away during consent.
  deadline(s,seconds+5);emit(s,extra+mapOf("type" to type,"decisionId" to id))
  val answer=s.decisions.poll(seconds,TimeUnit.SECONDS)==true;s.decisionId=0;checkRunning(s);return answer
 }
 private fun send(s:Session,address:String,path:String){
  val a=adapter?:throw IOException("Bluetooth unavailable")
  val device=a.getRemoteDevice(address)
  if(device.bondState!=BluetoothDevice.BOND_BONDED)throw IOException("Pair in Android settings first")
  val file=File(path);if(!file.isFile)throw IOException("Missing encrypted file")
  val length=file.length();if(length<1||length>1074790400L)throw IOException("Size limit")
  checkRunning(s);a.cancelDiscovery()
  val socket=device.createRfcommSocketToServiceRecord(service);s.socket=socket
  checkRunning(s);deadline(s,20);socket.connect();checkRunning(s)
  val out=DataOutputStream(BufferedOutputStream(socket.outputStream,65536));val input=DataInputStream(socket.inputStream)
  out.writeInt(0x56444231);out.writeLong(length);out.flush();deadline(s,70)
  if(input.read()!=1)throw IOException("Receiver declined")
  file.inputStream().use { source ->
   val buffer=ByteArray(65536);var sent=0L;var reported=0L
   while(true){checkRunning(s);val n=source.read(buffer);if(n<0)break;deadline(s,30);out.write(buffer,0,n);sent+=n
    val now=System.nanoTime();if(now-reported>TimeUnit.MILLISECONDS.toNanos(100)||sent==length){reported=now;emit(s,mapOf("type" to "progress","done" to sent,"total" to length))}
   }
  }
  out.flush();deadline(s,185);if(input.read()!=2)throw IOException("Receiver verification failed");checkRunning(s)
 }
 private fun listen(s:Session){
  val server=adapter?.listenUsingRfcommWithServiceRecord("ViaDrop",service)?:throw IOException("Bluetooth unavailable")
  s.server=server;checkRunning(s);ready(s)
  while(s.running){
   s.deadline=Long.MAX_VALUE
   val socket=server.accept();s.socket=socket;var file:File?=null
   try {
    checkRunning(s);deadline(s,15)
    if(socket.remoteDevice.bondState!=BluetoothDevice.BOND_BONDED)throw IOException("Unpaired peer")
    val input=DataInputStream(BufferedInputStream(socket.inputStream,65536));val out=socket.outputStream
    if(input.readInt()!=0x56444231)throw IOException("Invalid header")
    val length=input.readLong();if(length<1||length>1074790400L)throw IOException("Size limit")
    if(!decide(s,"offer",mapOf("name" to (socket.remoteDevice.name?:socket.remoteDevice.address),"size" to length),60)){out.write(0);out.flush();continue}
    out.write(1);out.flush();file=File.createTempFile("bt-",".vdp",activity.cacheDir)
    file.outputStream().buffered(65536).use { target ->
     val buffer=ByteArray(65536);var done=0L;var reported=0L
     while(done<length){checkRunning(s);deadline(s,30);val n=input.read(buffer,0,minOf(buffer.size.toLong(),length-done).toInt());if(n<=0)throw EOFException("Incomplete file")
      target.write(buffer,0,n);done+=n;val now=System.nanoTime()
      if(now-reported>TimeUnit.MILLISECONDS.toNanos(100)||done==length){reported=now;emit(s,mapOf("type" to "progress","done" to done,"total" to length))}
     }
    }
    val verified=decide(s,"file",mapOf("path" to file.absolutePath),180)
    out.write(if(verified)2 else 0);out.flush()
   }catch(e:Exception){if(s.running)emit(s,mapOf("type" to "error","message" to (e.message?:"Bluetooth receive failed")))}
   finally{file?.delete();try{socket.close()}catch(_:IOException){};if(s.socket===socket)s.socket=null;s.deadline=Long.MAX_VALUE}
  }
 }
 private fun close(s:Session){try{s.socket?.close()}catch(_:IOException){};try{s.server?.close()}catch(_:IOException){};s.decisions.offer(false)}
 private fun stop(s:Session,result:MethodChannel.Result?=null){
  if(result!=null)s.stops.add(result)
  s.running=false;s.decisionId=0;s.decisions.offer(false)
  // BluetoothSocket.close unblocks connect/read/accept. Never wait on UI thread.
  guard.execute{close(s)}
 }
 fun stopAll(){active?.let{stop(it)}}
 fun dispose(){disposed=true;val s=active;if(s!=null)stop(s)else{io.shutdown();guard.shutdown()}}
}
