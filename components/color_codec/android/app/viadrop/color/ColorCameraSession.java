// SPDX-License-Identifier: MPL-2.0
// Copyright 2026 Mahmoud Abiad
package app.viadrop.color;

import android.content.Context;
import android.graphics.ImageFormat;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.Image;
import android.media.ImageReader;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Size;
import android.view.Surface;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicInteger;

/** Camera2 pixel receiver, API23+. No permission requests or network operations.
 * All public lifecycle methods and listener callbacks run on the main thread.
 * The caller owns any preview Surface, its size/rotation and CAMERA permission.
 * Stop on app pause; close permanently on disposal. Native decode is not
 * interruptible: stop immediately suppresses results, then releases its Image
 * and ImageReader in order when the one active decode finishes.
 */
public final class ColorCameraSession implements AutoCloseable {
    public interface Listener {
        void onReady(int width, int height);
        void onPacket(byte[] packet);
        void onError(String code, String message);
    }

    private final CameraManager manager;
    private final Listener listener;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final HandlerThread cameraThread = new HandlerThread("ViaDrop-color-camera");
    private final HandlerThread decodeThread = new HandlerThread("ViaDrop-color-decode");
    private final Handler cameraHandler, decodeHandler;
    private final AtomicLong generation = new AtomicLong();
    private final AtomicBoolean decoding = new AtomicBoolean();
    private final AtomicBoolean delivering = new AtomicBoolean();
    // Accessed only on cameraHandler. Resources belong to this session, never
    // to callback arguments from an older open/configure request.
    private CameraDevice device;
    private CameraCaptureSession capture;
    private ImageReader reader;
    private boolean closed; // main thread only
    private boolean disposing; // camera handler only
    private int outstandingDevices; // includes asynchronous open requests
    private boolean cameraFinished;
    private final AtomicInteger releasedParts = new AtomicInteger();
    private Runnable onReleased;

    public ColorCameraSession(Context context, Listener listener) {
        requireMain();
        if (context == null || listener == null) throw new IllegalArgumentException("Missing context/listener");
        this.manager = (CameraManager)context.getApplicationContext().getSystemService(Context.CAMERA_SERVICE);
        if (manager == null) throw new IllegalStateException("Camera service unavailable");
        this.listener = listener;
        cameraThread.start(); decodeThread.start();
        cameraHandler = new Handler(cameraThread.getLooper());
        decodeHandler = new Handler(decodeThread.getLooper());
    }

    /** Explicit matrix/rotation; never infer that all cameras use BT.601.
     * Size must be an advertised YUV size, at most 2.1 MP (including 1920x1080). A supplied preview
     * surface must also have been configured to a supported output size.
     */
    public void start(String cameraId, Size size, Surface preview,
                      int clockwiseDegrees, Yuv420Rgb.Matrix matrix) {
        requireMain();
        if (closed) throw new IllegalStateException("Camera session disposed");
        if (cameraId == null || size == null || matrix == null ||
            size.getWidth() < 1 || size.getHeight() < 1 ||
            (long)size.getWidth()*size.getHeight() > 2100000 ||
            (clockwiseDegrees != 0 && clockwiseDegrees != 90 && clockwiseDegrees != 180 && clockwiseDegrees != 270) ||
            (preview != null && !preview.isValid())) throw new IllegalArgumentException("Camera configuration");
        long token = generation.incrementAndGet();
        cameraHandler.post(new Runnable() { @Override public void run() {
            releaseCamera();
            if (generation.get() != token) return;
            try {
                CameraCharacteristics characteristics = manager.getCameraCharacteristics(cameraId);
                StreamConfigurationMap map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
                boolean supported = false;
                if (map != null) {
                    Size[] sizes = map.getOutputSizes(ImageFormat.YUV_420_888);
                    if (sizes != null) for (Size candidate : sizes) if (candidate.equals(size)) supported = true;
                }
                if (!supported) throw new IllegalArgumentException("YUV capture size unavailable");
                final ImageReader output = ImageReader.newInstance(size.getWidth(), size.getHeight(), ImageFormat.YUV_420_888, 3);
                reader = output;
                output.setOnImageAvailableListener(new ImageReader.OnImageAvailableListener() {
                    @Override public void onImageAvailable(ImageReader source) {
                        acquire(source, token, clockwiseDegrees, matrix);
                    }
                }, cameraHandler);
                CameraDevice.StateCallback callback = new CameraDevice.StateCallback() {
                    @Override public void onOpened(CameraDevice opened) {
                        if (generation.get() != token) { opened.close(); return; }
                        device = opened;
                        configure(opened, output, preview, token, size, characteristics);
                    }
                    @Override public void onDisconnected(CameraDevice disconnected) {
                        disconnected.close();
                        fail(token, "CAMERA_DISCONNECTED", "Camera disconnected");
                    }
                    @Override public void onError(CameraDevice failed, int error) {
                        failed.close();
                        fail(token, "CAMERA_OPEN", "Camera error " + error);
                    }
                    @Override public void onClosed(CameraDevice retired) {
                        outstandingDevices--;
                        finishCameraThread();
                    }
                };
                outstandingDevices++;
                try { manager.openCamera(cameraId, callback, cameraHandler); }
                catch (Exception e) { outstandingDevices--; throw e; }
            } catch (Exception e) { fail(token, "CAMERA_START", detail(e)); }
        }});
    }

    private void configure(CameraDevice opened, ImageReader output, Surface preview,
                           long token, Size size, CameraCharacteristics characteristics) {
        try {
            List<Surface> targets = new ArrayList<>();
            targets.add(output.getSurface());
            if (preview != null) targets.add(preview);
            opened.createCaptureSession(targets, new CameraCaptureSession.StateCallback() {
                @Override public void onConfigured(CameraCaptureSession configured) {
                    if (generation.get() != token) { configured.close(); return; }
                    capture = configured;
                    try {
                        CaptureRequest.Builder request = opened.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
                        for (Surface target : targets) request.addTarget(target);
                        request.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO);
                        int[] modes = characteristics.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES);
                        if (modes != null) for (int mode : modes) {
                            if (mode == CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE) {
                                request.set(CaptureRequest.CONTROL_AF_MODE, mode); break;
                            }
                        }
                        configured.setRepeatingRequest(request.build(), null, cameraHandler);
                        main.post(new Runnable() { @Override public void run() {
                            if (generation.get() == token) listener.onReady(size.getWidth(), size.getHeight());
                        }});
                    } catch (Exception e) { fail(token, "CAMERA_CAPTURE", detail(e)); }
                }
                @Override public void onConfigureFailed(CameraCaptureSession failed) {
                    failed.close(); fail(token, "CAMERA_CONFIGURE", "Camera output configuration rejected");
                }
            }, cameraHandler);
        } catch (Exception e) { fail(token, "CAMERA_CONFIGURE", detail(e)); }
    }

    private void acquire(ImageReader source, long token, int rotation, Yuv420Rgb.Matrix matrix) {
        Image image = null;
        try {
            image = source.acquireLatestImage();
            if (image == null) return;
            if (generation.get() != token || !decoding.compareAndSet(false, true)) {
                image.close(); return;
            }
            final Image owned = image;
            if (!decodeHandler.post(new Runnable() { @Override public void run() {
                try {
                    if (generation.get() != token) { owned.close(); return; }
                    // decodeAndClose owns Image even when conversion/native code fails.
                    byte[] packet = CameraImageDecoder.decodeAndClose(owned, rotation, matrix);
                    if (packet != null && delivering.compareAndSet(false, true)) main.post(new Runnable() { @Override public void run() {
                        try { if (generation.get() == token) listener.onPacket(packet); }
                        finally { delivering.set(false); }
                    }});
                } catch (RuntimeException | LinkageError e) {
                    fail(token, "COLOR_DECODE", detail(e));
                } finally { decoding.set(false); }
            }})) {
                owned.close(); decoding.set(false);
                fail(token, "COLOR_WORKER", "Decode worker stopped");
            }
        } catch (RuntimeException e) {
            if (image != null) image.close();
            fail(token, "CAMERA_FRAME", detail(e));
        }
    }

    /** Invalidates callbacks immediately; resources release asynchronously. */
    public void stop() {
        requireMain();
        if (closed) return;
        generation.incrementAndGet();
        cameraHandler.post(new Runnable() { @Override public void run() { releaseCamera(); }});
    }

    /** Caller may release its preview Surface from onReleased, after camera
     * device close and completion of the last image decode. Call only once.
     */
    public void close(Runnable onReleased) {
        requireMain();
        if (closed) return;
        this.onReleased = onReleased;
        closed = true;
        generation.incrementAndGet();
        cameraHandler.post(new Runnable() { @Override public void run() {
            disposing = true;
            releaseCamera();
            // releaseCamera queues reader.close behind the only in-flight decode.
            decodeHandler.post(new Runnable() { @Override public void run() {
                decodeThread.quitSafely();
                releasedPart();
            }});
            finishCameraThread();
        }});
    }

    @Override public void close() { close(null); }

    private void releasedPart() {
        if (releasedParts.incrementAndGet() == 2 && onReleased != null) main.post(onReleased);
    }

    private void finishCameraThread() {
        // Keep the callback looper alive until a pending open has delivered a
        // device and its close callback. Otherwise stop-during-open can leak it.
        if (disposing && outstandingDevices == 0 && !cameraFinished) {
            cameraFinished = true;
            cameraThread.quitSafely();
            releasedPart();
        }
    }

    private void releaseCamera() {
        if (capture != null) { capture.close(); capture = null; }
        if (device != null) { device.close(); device = null; }
        if (reader != null) {
            ImageReader retired = reader; reader = null;
            retired.setOnImageAvailableListener(null, null);
            // Closing ImageReader while a worker reads its planes invalidates
            // those buffers. FIFO on the decode handler keeps them valid.
            decodeHandler.post(new Runnable() { @Override public void run() { retired.close(); }});
        }
    }

    private void fail(long token, String code, String message) {
        main.post(new Runnable() { @Override public void run() {
            if (generation.get() != token) return;
            stop();
            listener.onError(code, message);
        }});
    }
    private static String detail(Throwable error) {
        return error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
    }
    private static void requireMain() {
        if (Looper.myLooper() != Looper.getMainLooper()) throw new IllegalStateException("Camera lifecycle requires main thread");
    }
}
