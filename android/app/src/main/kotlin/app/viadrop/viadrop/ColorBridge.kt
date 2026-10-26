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
    private var generation = 0L
    private var texture: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var renderer: ColorFrameRenderer? = null
    private var camera: ColorCameraSession? = null
    private var frameResult: MethodChannel.Result? = null
    private var startingResult: MethodChannel.Result? = null
    private var stopping = false
    private var disposed = false

    init {
        EventChannel(engine.dartExecutor.binaryMessenger, "app.viadrop/color-events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) { sink = events }
                override fun onCancel(args: Any?) { sink = null; stop(null) }
            })
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.viadrop/color")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "probe" -> result.success(available())
                        "stop" -> stop { result.success(null) }
                        "senderStart" -> {
                            checkIdle()
                            check(available()) { "Native color codec unavailable" }
                            val token = ++generation
                            val entry = registry.createSurfaceTexture()
                            texture = entry
                            entry.surfaceTexture().setDefaultBufferSize(1024, 1024)
                            val output = Surface(entry.surfaceTexture())
                            surface = output
                            renderer = ColorFrameRenderer(output, object : ColorFrameRenderer.Listener {
                                override fun onPresented() {
                                    if (generation == token) { frameResult?.success(true); frameResult = null }
                                }
                                override fun onError(message: String) {
                                    if (generation == token) {
                                        frameResult?.error("COLOR_DISPLAY", message, null); frameResult = null
                                        event(token, mapOf("type" to "error", "message" to message))
                                    }
                                }
                            })
                            result.success(mapOf("generation" to token, "textureId" to entry.id(), "width" to 1024, "height" to 1024))
                        }
                        "senderFrame" -> {
                            val data = call.argument<ByteArray>("data") ?: error("Missing packet")
                            check(data.isNotEmpty() && data.size <= 4096) { "Invalid packet length" }
                            check(frameResult == null) { "A color frame is already pending" }
                            val output = renderer ?: error("Color sender is not active")
                            frameResult = result
                            if (!output.present(data)) { frameResult = null; result.success(false) }
                        }
                        "receiverStart" -> {
                            checkIdle()
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
                            val size = sizes.filter { it.width.toLong()*it.height in 1_000_000L..2_000_000L }
                                .maxByOrNull { it.width.toLong()*it.height } ?: error("No supported 1–2 MP camera output")
                            val token = ++generation
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
                                    if (generation != token) return
                                    startingResult?.success(mapOf("generation" to token, "textureId" to entry.id(), "width" to width, "height" to height, "rotation" to rotation))
                                    startingResult = null
                                }
                                override fun onPacket(packet: ByteArray) { event(token, mapOf("type" to "packet", "data" to packet)) }
                                override fun onError(code: String, message: String) {
                                    if (generation != token) return
                                    startingResult?.error(code, message, null); startingResult = null
                                    event(token, mapOf("type" to "error", "message" to message))
                                    stop(null)
                                }
                            })
                            camera!!.start(id, size, preview, rotation, matrix)
                            main.postDelayed({
                                if (generation == token && startingResult != null) {
                                    startingResult?.error("COLOR_TIMEOUT", "Camera did not start within 10 seconds", null)
                                    startingResult = null; stop(null)
                                }
                            }, 10_000)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    if (frameResult === result) frameResult = null
                    if (startingResult === result) startingResult = null
                    result.error("COLOR_NATIVE", e.message ?: e.javaClass.simpleName, null)
                    if (call.method == "senderStart" || call.method == "receiverStart") stop(null)
                }
            }
    }

    private fun available(): Boolean = try {
        val dimensions = ColorCodec.dimensions()
        dimensions.size == 2 && dimensions[0] == 1024 && dimensions[1] == 1024
    } catch (_: Throwable) { false }

    private fun checkIdle() { check(!disposed && !stopping && camera == null && renderer == null && texture == null) { "Color session busy or disposed" } }
    private fun event(token: Long, data: Map<String, Any>) { if (generation == token && !disposed) sink?.success(data + mapOf("generation" to token)) }

    /** Native cleanup completion precedes Surface/texture release. */
    fun stop(after: (() -> Unit)?) {
        if (stopping) { main.postDelayed({ stop(after) }, 20); return }
        generation++
        startingResult?.error("COLOR_CANCELLED", "Camera session cancelled", null); startingResult = null
        frameResult?.error("COLOR_CANCELLED", "Color display cancelled", null); frameResult = null
        val oldCamera = camera; camera = null
        val oldRenderer = renderer; renderer = null
        val oldSurface = surface; surface = null
        val oldTexture = texture; texture = null
        stopping = true
        val released = Runnable {
            oldSurface?.release(); oldTexture?.release()
            stopping = false; after?.invoke()
        }
        if (oldCamera != null) oldCamera.close(released)
        else if (oldRenderer != null) oldRenderer.close(released)
        else released.run()
    }
    fun dispose() { disposed = true; stop(null); sink = null }
}
