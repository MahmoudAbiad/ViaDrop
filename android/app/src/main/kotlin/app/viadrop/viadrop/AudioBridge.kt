package app.viadrop.viadrop

import android.content.Context
import android.content.pm.PackageManager
import android.media.*
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

interface AudioCodec {
    fun waveInit(): Long
    fun waveFree(handle: Long)
    fun waveEncode(handle: Long, data: ByteArray, high: Boolean): ByteArray?
    fun waveDecode(handle: Long, data: ByteArray, count: Int): ByteArray?
    fun ofdmInit(): Long
    fun ofdmFree(handle: Long)
    fun ofdmEncode(data: ByteArray): ByteArray?
    fun ofdmDecode(handle: Long, data: ByteArray): ByteArray?
}

/** Owns microphone/speaker sessions, never file paths or radio transport.
 * API23 nonblocking PCM I/O permits cancellation without releasing an object
 * underneath a worker. Stop replies only after ALL workers free their resources.
 */
class AudioBridge(private val context: Context, engine: FlutterEngine, private val codec: AudioCodec) {
    private val main = Handler(Looper.getMainLooper())
    private val workers = ThreadPoolExecutor(3, 3, 15L, TimeUnit.SECONDS,
        ArrayBlockingQueue<Runnable>(4)).apply { allowCoreThreadTimeOut(true) }
    private val lifecycle = NativeSessionState { error -> android.util.Log.e("ViaDropAudio", "Cleanup reply failed", error) }
    private var sink: EventChannel.EventSink? = null
    private var session: Session? = null
    private var disposed = false

    private class Session(val client: Long, val generation: Long, val listening: Boolean, val fast: Boolean) {
        val running = AtomicBoolean(true)
        val drain = SessionWorkDrain()
        val pcm = ArrayBlockingQueue<ByteArray>(48)
        var startReply: MethodChannel.Result? = null
        var playReply: MethodChannel.Result? = null
        var timeout: Runnable? = null
        var readerReady = false
        var decoderReady = !fast
    }

    init {
        EventChannel(engine.dartExecutor.binaryMessenger, "app.viadrop/audio-events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) { sink = events }
                override fun onCancel(args: Any?) {
                    sink = null
                    // Normal shared-observer cancellation does not own hardware.
                    // Null separates stream registrations during a hot restart.
                    if (args == null) stop(null)
                }
            })
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.viadrop/audio")
            .setMethodCallHandler { call, result ->
                var acquired: Session? = null
                try {
                    val client = call.argument<Number>("clientId")?.toLong() ?: error("Missing audio client")
                    require(client > 0) { "Invalid audio client" }
                    when (call.method) {
                        "openSend", "listen" -> {
                            val listening = call.method == "listen"
                            if (listening) check(context.checkSelfPermission("android.permission.RECORD_AUDIO") == PackageManager.PERMISSION_GRANTED) { "Microphone permission denied" }
                            val token = lifecycle.begin(client)
                            val s = Session(client, token, listening, call.argument<Boolean>("fast") == true)
                            session = s; acquired = s
                            if (!listening) result.success(mapOf("generation" to token))
                            else {
                                s.startReply = result
                                val timeout = Runnable {
                                    if (current(s) && s.startReply != null) fail(s, IOException("Microphone start timed out"))
                                }
                                s.timeout = timeout; main.postDelayed(timeout, 10_000)
                                if (s.fast) launch(s) { decodeOfdm(s) }
                                launch(s) { readMicrophone(s) }
                            }
                        }
                        "play" -> {
                            val s = session ?: error("Audio sender not active")
                            check(lifecycle.owns(client) && current(s) && !s.listening) { "Audio packet belongs to another session" }
                            check(s.playReply == null) { "Previous audio packet is still playing" }
                            val data = call.argument<ByteArray>("data") ?: error("Missing audio data")
                            val fast = call.argument<Boolean>("fast") == true
                            val high = call.argument<Boolean>("high") == true
                            require(data.isNotEmpty() && data.size <= (if (fast) 1024 else 140)) { "Audio packet length" }
                            require(!fast || !high) { "OFDM high frequency is unavailable" }
                            s.playReply = result
                            try { launch(s) {
                                playPacket(s, data, fast, high)
                                main.post {
                                    if (current(s)) { val reply = s.playReply; s.playReply = null; successReply(s, reply, null) }
                                }
                            } } catch (error: Throwable) { s.playReply = null; throw error }
                        }
                        "stop" -> stop({ result.success(null) }, client)
                        else -> result.notImplemented()
                    }
                } catch (error: Throwable) {
                    val s = acquired
                    if (s?.startReply === result) s.startReply = null
                    errorReply(result, "AUDIO_NATIVE", error.message ?: error.javaClass.simpleName)
                    if (s != null && lifecycle.isCurrent(s.generation)) stop(null, s.client)
                }
            }
    }

    private fun errorReply(reply: MethodChannel.Result?, code: String, message: String) {
        try { reply?.error(code, message, null) }
        catch (error: RuntimeException) { android.util.Log.e("ViaDropAudio", "Audio reply failed", error) }
    }
    private fun successReply(s: Session, reply: MethodChannel.Result?, value: Any?) {
        try { reply?.success(value) }
        catch (error: RuntimeException) {
            android.util.Log.e("ViaDropAudio", "Audio reply failed", error)
            if (lifecycle.isCurrent(s.generation)) stop(null, s.client)
        }
    }
    private fun current(s: Session) = session === s && s.running.get() && lifecycle.isCurrent(s.generation)
    private fun event(s: Session, values: Map<String, Any>) {
        main.post { if (current(s)) sink?.success(values + mapOf("clientId" to s.client, "generation" to s.generation)) }
    }
    private fun ready(s: Session, reader: Boolean) {
        main.post {
            if (!current(s)) return@post
            if (reader) s.readerReady = true else s.decoderReady = true
            if (s.readerReady && s.decoderReady) {
                cancelTimeout(s)
                val reply = s.startReply; s.startReply = null
                successReply(s, reply, mapOf("generation" to s.generation))
            }
        }
    }
    private fun fail(s: Session, error: Throwable) {
        main.post {
            if (session !== s || !lifecycle.isCurrent(s.generation)) return@post
            val message = error.message ?: error.javaClass.simpleName
            val start = s.startReply; s.startReply = null
            val play = s.playReply; s.playReply = null
            errorReply(start, "AUDIO_NATIVE", message)
            errorReply(play, "AUDIO_NATIVE", message)
            sink?.success(mapOf("type" to "error", "message" to message, "clientId" to s.client, "generation" to s.generation))
            stop(null, s.client)
        }
    }
    private fun launch(s: Session, work: () -> Unit) {
        val ticket = s.drain.begin()
        try { workers.execute {
            try { if (s.running.get()) work() }
            catch (error: Throwable) { if (s.running.get()) fail(s, error) }
            finally { main.post { s.drain.complete(ticket) } }
        } } catch (error: Throwable) { s.drain.complete(ticket); throw error }
    }

    private fun playPacket(s: Session, data: ByteArray, fast: Boolean, high: Boolean) {
        var handle = -1L
        var player: AudioTrack? = null
        try {
            if (!s.running.get()) return
            val pcm = if (fast) codec.ofdmEncode(data) else {
                handle = codec.waveInit()
                check(handle >= 0) { "Audio encoder unavailable" }
                codec.waveEncode(handle, data, high)
            } ?: throw IOException("Audio encoding failed")
            require(pcm.isNotEmpty() && pcm.size % 2 == 0 && pcm.size <= 2_880_000) { "Invalid PCM waveform" }
            if (!s.running.get()) return
            val samples = ShortArray(pcm.size / 2)
            ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(samples)
            val min = AudioTrack.getMinBufferSize(48000, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
            check(min > 0) { "PCM playback unavailable" }
            val output = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setAudioFormat(AudioFormat.Builder().setSampleRate(48000).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                .setBufferSizeInBytes(maxOf(min, 8192)).setTransferMode(AudioTrack.MODE_STREAM).build()
            player = output
            check(output.state == AudioTrack.STATE_INITIALIZED) { "Speaker initialization failed" }
            if (!s.running.get()) return
            output.play()
            val deadline = SystemClock.elapsedRealtime() + samples.size * 1000L / 48000 + 5000
            var offset = 0
            while (s.running.get() && offset < samples.size) {
                if (SystemClock.elapsedRealtime() > deadline) throw IOException("Speaker write timed out")
                val n = output.write(samples, offset, minOf(2048, samples.size-offset), AudioTrack.WRITE_NON_BLOCKING)
                if (n < 0) throw IOException("Speaker write failed: $n")
                offset += n
                if (n == 0) Thread.sleep(5)
            }
            while (s.running.get() && (output.playbackHeadPosition.toLong() and 0xffffffffL) < samples.size) {
                if (SystemClock.elapsedRealtime() > deadline) throw IOException("Speaker playback timed out")
                Thread.sleep(10)
            }
        } finally {
            try { if (player != null) { try { player.stop() } catch (_: Exception) {} ; player.release() } }
            finally { if (handle >= 0) codec.waveFree(handle) }
        }
    }

    private fun readMicrophone(s: Session) {
        var handle = -1L
        var input: AudioRecord? = null
        try {
            handle = codec.waveInit(); check(handle >= 0) { "Audio decoder unavailable" }
            if (!s.running.get()) return
            val min = AudioRecord.getMinBufferSize(48000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            check(min > 0) { "PCM microphone unavailable" }
            val recording = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 48000,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, 8192))
            input = recording
            check(recording.state == AudioRecord.STATE_INITIALIZED) { "Microphone initialization failed" }
            if (!s.running.get()) return
            recording.startRecording(); ready(s, true)
            val samples = ShortArray(1024)
            val bytes = ByteArray(2048)
            val packed = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
            // Bind the original Buffer setter signature on legacy Android,
            // rather than a newer SDK's covariant ShortBuffer overload.
            val cursor: java.nio.Buffer = packed
            var lastRead = SystemClock.elapsedRealtime()
            while (s.running.get()) {
                val n = recording.read(samples, 0, samples.size, AudioRecord.READ_NON_BLOCKING)
                if (!s.running.get()) break
                if (n < 0) throw IOException("Microphone read failed: $n")
                if (n == 0) {
                    if (SystemClock.elapsedRealtime()-lastRead > 3000) throw IOException("Microphone produced no PCM")
                    Thread.sleep(5); continue
                }
                lastRead = SystemClock.elapsedRealtime()
                cursor.position(0); packed.put(samples, 0, n)
                if (s.fast) {
                    val copy = bytes.copyOf(n*2)
                    if (!s.pcm.offer(copy)) { s.pcm.clear(); s.pcm.offer(copy) }
                }
                codec.waveDecode(handle, bytes, n*2)?.let { event(s, mapOf("type" to "audioData", "data" to it)) }
            }
        } finally {
            try { if (input != null) { try { input.stop() } catch (_: Exception) {} ; input.release() } }
            finally { if (handle >= 0) codec.waveFree(handle) }
        }
    }
    private fun decodeOfdm(s: Session) {
        var handle = 0L
        try {
            handle = codec.ofdmInit(); check(handle != 0L) { "OFDM decoder unavailable" }; ready(s, false)
            while (s.running.get()) {
                val pcm = s.pcm.poll(200, TimeUnit.MILLISECONDS) ?: continue
                if (!s.running.get()) break
                if (pcm.isNotEmpty()) codec.ofdmDecode(handle, pcm)?.let { event(s, mapOf("type" to "audioData", "data" to it)) }
            }
        } finally { if (handle != 0L) codec.ofdmFree(handle) }
    }
    private fun cancelTimeout(s: Session) { s.timeout?.let { main.removeCallbacks(it) }; s.timeout = null }

    fun stop(after: (() -> Unit)?, client: Long? = null) {
        val completion = after?.let { Runnable { it() } }
        val ticket = if (client == null) lifecycle.stop(completion) else lifecycle.stopOwned(client, completion)
        if (ticket == 0L) return
        val s = session ?: error("Active audio session missing")
        s.running.set(false); cancelTimeout(s)
        val start = s.startReply; s.startReply = null; errorReply(start, "AUDIO_CANCELLED", "Audio session cancelled")
        val play = s.playReply; s.playReply = null; errorReply(play, "AUDIO_CANCELLED", "Audio playback cancelled")
        // Both PCM loops are nonblocking. The owner worker observes running
        // and stops/releases its own hardware in finally; UI never calls a
        // driver stop/release or races a worker that is still using the object.
        s.pcm.clear(); s.pcm.offer(ByteArray(0))
        s.drain.seal {
            if (session === s) session = null
            lifecycle.finishStop(ticket)
            if (disposed) workers.shutdown()
        }
    }
    fun dispose() { disposed = true; lifecycle.disallowStarts(); sink = null; stop(null); if (session == null) workers.shutdown() }
}
