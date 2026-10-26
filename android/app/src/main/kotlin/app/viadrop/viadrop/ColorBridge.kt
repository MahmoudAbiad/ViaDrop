package app.viadrop.viadrop

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Handler
import android.os.Looper
import android.view.Surface
import app.viadrop.color.ColorCameraSession
import app.viadrop.color.ColorCodec
import app.viadrop.color.ColorFrameRenderer
import app.viadrop.color.Yuv420Rgb
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/** Flutter owns navigation; this bridge owns the optical native resources.
 * A separate event channel cannot be mistaken for radio/audio events.
 */
class ColorBridge(private val activity: Activity, engine: FlutterEngine) {
    private val main = Handler(Looper.getMainLooper())
    private val registry = engine.renderer
    private var sink: EventChannel.EventSink? = null
    private val lifecycle = ColorSessionState { error ->
        android.util.Log.e("ViaDropColor", "Cleanup reply failed", error)
    }
    private var texture: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var renderer: ColorFrameRenderer? = null
    private var camera: ColorCameraSession? = null
    private var frameResult: MethodChannel.Result? = null
    private var startingResult: MethodChannel.Result? = null
    private var startTimeout: Runnable? = null

    init {
        EventChannel(engine.dartExecutor.binaryMessenger, "app.viadrop/color-events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) { sink = events }
                override fun onCancel(args: Any?) {
                    sink = null
                    // Ordinary observation does not own capture resources. Each
                    // screen explicitly stops its client, even during disposal.
                    // Null is the embedding's documented hot-restart separator;
                    // normal Dart cancellations always carry observer arguments.
                    if (args == null) stop(null)
                }
            })
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.viadrop/color")
            .setMethodCallHandler { call, result ->
                // Only this request's successful acquisition may be rolled back.
                // A rejected duplicate start never owns the active session.
                var ownedStart: Long? = null
                fun clientId(): Long {
                    val client = call.argument<Number>("clientId")?.toLong() ?: error("Missing color client")
                    check(client > 0) { "Invalid color client" }
                    return client
                }
                try {
                    when (call.method) {
                        "probe" -> result.success(available())
                        "stop" -> stop({ result.success(null) }, clientId(), call.argument<Number>("generation")?.toLong())
                        "senderStart" -> {
                            check(available()) { "Native color codec unavailable" }
                            val token = lifecycle.begin(clientId()).also { ownedStart = it }
                            val entry = registry.createSurfaceTexture()
                            texture = entry
                            entry.surfaceTexture().setDefaultBufferSize(1024, 1024)
                            val output = Surface(entry.surfaceTexture())
                            surface = output
                            renderer = ColorFrameRenderer(output, object : ColorFrameRenderer.Listener {
                                override fun onPresented() {
                                    if (lifecycle.isCurrent(token)) {
                                        val reply = frameResult; frameResult = null
                                        reply?.success(true)
                                    }
                                }
                                override fun onError(message: String) {
                                    if (lifecycle.isCurrent(token)) {
                                        frameResult?.error("COLOR_DISPLAY", message, null); frameResult = null
                                        event(token, mapOf("type" to "error", "message" to message))
                                    }
                                }
                            })
                            result.success(mapOf("generation" to token, "textureId" to entry.id(), "width" to 1024, "height" to 1024))
                        }
                        "senderFrame" -> {
                            check(lifecycle.owns(clientId())) { "Color frame belongs to another session" }
                            val data = call.argument<ByteArray>("data") ?: error("Missing packet")
                            check(data.isNotEmpty() && data.size <= 4096) { "Invalid packet length" }
                            check(frameResult == null) { "A color frame is already pending" }
                            val output = renderer ?: error("Color sender is not active")
                            frameResult = result
                            if (!output.present(data)) { frameResult = null; result.success(false) }
                        }
                        "receiverStart" -> {
                            check(available()) { "Native color codec unavailable" }
                            check(activity.checkSelfPermission("android.permission.CAMERA") == PackageManager.PERMISSION_GRANTED) { "Camera permission denied" }
                            val matrix = when (call.argument<String>("matrix")) {
                                "bt601" -> Yuv420Rgb.Matrix.BT601_LIMITED
                                "bt709" -> Yuv420Rgb.Matrix.BT709_LIMITED
                                else -> error("Select an explicit limited-range color matrix")
                            }
                            val manager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
                            val id = manager.cameraIdList.firstOrNull {
                                manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
                            } ?: error("Rear camera unavailable")
                            val chars = manager.getCameraCharacteristics(id)
                            val sizes = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                                ?.getOutputSizes(ImageFormat.YUV_420_888) ?: error("YUV capture unavailable")
                            val size = sizes.filter { minOf(it.width, it.height) >= 720 && it.width.toLong()*it.height <= 2_100_000L }
                                .maxByOrNull { it.width.toLong()*it.height } ?: error("No supported 720p–1080p camera output")
                            val token = lifecycle.begin(clientId()).also { ownedStart = it }
                            val entry = registry.createSurfaceTexture()
                            texture = entry
                            entry.surfaceTexture().setDefaultBufferSize(size.width, size.height)
                            val preview = Surface(entry.surfaceTexture())
                            surface = preview
                            val displayRotation = activity.windowManager.defaultDisplay.rotation
                            val degrees = when (displayRotation) { Surface.ROTATION_90 -> 90; Surface.ROTATION_180 -> 180; Surface.ROTATION_270 -> 270; else -> 0 }
                            val rotation = ((chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0)-degrees+360)%360
                            startingResult = result
                            camera = ColorCameraSession(activity, object : ColorCameraSession.Listener {
                                override fun onReady(width: Int, height: Int) {
                                    if (!lifecycle.isCurrent(token)) return
                                    cancelStartTimeout()
                                    startingResult?.success(mapOf("generation" to token, "textureId" to entry.id(), "width" to width, "height" to height, "rotation" to rotation))
                                    startingResult = null
                                }
                                override fun onPacket(packet: ByteArray) { event(token, mapOf("type" to "packet", "data" to packet)) }
                                override fun onError(code: String, message: String) {
                                    if (!lifecycle.isCurrent(token)) return
                                    cancelStartTimeout()
                                    startingResult?.error(code, message, null); startingResult = null
                                    event(token, mapOf("type" to "error", "message" to message))
                                    stop(null)
                                }
                            })
                            camera!!.start(id, size, preview, rotation, matrix)
                            val timeout = Runnable {
                                if (lifecycle.isCurrent(token) && startingResult != null) {
                                    startTimeout = null
                                    startingResult?.error("COLOR_TIMEOUT", "Camera did not start within 10 seconds", null)
                                    startingResult = null; stop(null)
                                }
                            }
                            startTimeout = timeout
                            main.postDelayed(timeout, 10_000)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    if (frameResult === result) frameResult = null
                    if (startingResult === result) startingResult = null
                    result.error("COLOR_NATIVE", e.message ?: e.javaClass.simpleName, null)
                    if (ownedStart?.let { lifecycle.isCurrent(it) } == true) stop(null)
                }
            }
    }

    private fun available(): Boolean = try {
        val dimensions = ColorCodec.dimensions()
        dimensions.size == 2 && dimensions[0] == 1024 && dimensions[1] == 1024
    } catch (_: Throwable) { false }

    private fun event(token: Long, data: Map<String, Any>) {
        if (lifecycle.isCurrent(token)) sink?.success(data + mapOf(
            "generation" to token, "clientId" to lifecycle.owner()))
    }

    private fun cancelStartTimeout() {
        startTimeout?.let { main.removeCallbacks(it) }
        startTimeout = null
    }

    /** Native cleanup completion precedes Surface/texture release. */
    fun stop(after: (() -> Unit)?, clientId: Long? = null, expectedGeneration: Long? = null) {
        val completed = after?.let { completion -> Runnable { completion() } }
        val ticket = if (clientId == null) lifecycle.stop(completed)
            else if (expectedGeneration != null) lifecycle.stopOwned(clientId, expectedGeneration, completed)
            else lifecycle.stopOwned(clientId, completed)
        if (ticket == 0L) return
        cancelStartTimeout()
        startingResult?.error("COLOR_CANCELLED", "Camera session cancelled", null); startingResult = null
        frameResult?.error("COLOR_CANCELLED", "Color display cancelled", null); frameResult = null
        val oldCamera = camera; camera = null
        val oldRenderer = renderer; renderer = null
        val oldSurface = surface; surface = null
        val oldTexture = texture; texture = null
        val released = Runnable {
            if (lifecycle.isStopping(ticket)) {
                try { oldSurface?.release() }
                finally {
                    try { oldTexture?.release() }
                    finally { lifecycle.finishStop(ticket) }
                }
            }
        }
        if (oldCamera != null) oldCamera.close(released)
        else if (oldRenderer != null) oldRenderer.close(released)
        else released.run()
    }
    fun dispose() { lifecycle.disallowStarts(); sink = null; stop(null) }
}
