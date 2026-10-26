// SPDX-License-Identifier: MPL-2.0
// Copyright 2026 Mahmoud Abiad
package app.viadrop.color;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.view.Surface;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/** Converts real packet bytes to CIMBAR pixels and presents them on a caller
 * owned Surface, suitable for a Flutter SurfaceTexture. No network operations.
 * Public methods/callbacks require main thread. One outstanding frame maximum;
 * false from present means backpressure, not a successful transmission.
 * onPresented means pixels were posted, never that another device received them.
 */
public final class ColorFrameRenderer implements AutoCloseable {
    public interface Listener {
        void onPresented();
        void onError(String message);
    }
    private final Handler main = new Handler(Looper.getMainLooper());
    private final HandlerThread thread = new HandlerThread("ViaDrop-color-display");
    private final Handler worker;
    private final AtomicBoolean busy = new AtomicBoolean();
    private final AtomicLong generation = new AtomicLong();
    private final Surface surface;
    private final Listener listener;
    private boolean closed;
    // Reused worker-owned buffers, not a list of RGB frames.
    private Bitmap bitmap;
    private int[] argb;
    private final Paint paint = new Paint();

    public ColorFrameRenderer(Surface surface, Listener listener) {
        requireMain();
        if (surface == null || listener == null || !surface.isValid()) throw new IllegalArgumentException("Missing display surface/listener");
        this.surface = surface;
        this.listener = listener;
        paint.setAntiAlias(false);
        paint.setFilterBitmap(false);
        paint.setDither(false);
        thread.start(); worker = new Handler(thread.getLooper());
    }

    public boolean present(byte[] packet) {
        requireMain();
        if (closed) throw new IllegalStateException("Renderer disposed");
        if (packet == null || packet.length < 1 || packet.length > 4096) throw new IllegalArgumentException("Packet length");
        if (!busy.compareAndSet(false, true)) return false;
        final long token = generation.get();
        final byte[] owned = packet.clone();
        boolean queued = worker.post(() -> render(owned, token));
        if (!queued) busy.set(false);
        return queued;
    }

    private void render(byte[] packet, long token) {
        String error = null;
        try {
            if (generation.get() != token) return;
            int[] dimensions = ColorCodec.dimensions();
            if (dimensions == null || dimensions.length != 2 || dimensions[0] != 1024 || dimensions[1] != 1024)
                throw new IllegalStateException("Unexpected color frame geometry");
            byte[] rgb = ColorCodec.encode(packet);
            if (rgb == null || rgb.length != 1024*1024*3) throw new IllegalStateException("Color encoder rejected packet");
            if (generation.get() != token) return;
            if (bitmap == null) {
                bitmap = Bitmap.createBitmap(1024, 1024, Bitmap.Config.ARGB_8888);
                argb = new int[1024*1024];
            }
            for (int i = 0, j = 0; i < argb.length; i++, j += 3) {
                argb[i] = 0xff000000 | ((rgb[j]&255)<<16) | ((rgb[j+1]&255)<<8) | (rgb[j+2]&255);
            }
            bitmap.setPixels(argb, 0, 1024, 0, 0, 1024, 1024);
            if (generation.get() != token) return;
            Canvas canvas = surface.lockCanvas(null);
            try {
                int edge = Math.min(canvas.getWidth(), canvas.getHeight());
                if (edge < 1024) throw new IllegalStateException("Color mode requires a surface at least 1024 pixels wide and high");
                // Integer scale prevents unequal cell widths and interpolation.
                edge = (edge/1024)*1024;
                int left = (canvas.getWidth()-edge)/2, top = (canvas.getHeight()-edge)/2;
                canvas.drawColor(Color.WHITE);
                canvas.drawBitmap(bitmap, null, new Rect(left, top, left+edge, top+edge), paint);
            } finally { surface.unlockCanvasAndPost(canvas); }
        } catch (RuntimeException | LinkageError e) {
            error = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
        } finally {
            final String failure = error;
            // Hold backpressure until the main callback consumes this result.
            main.post(() -> {
                busy.set(false);
                if (generation.get() != token) return;
                if (failure == null) listener.onPresented(); else listener.onError(failure);
            });
        }
    }

    /** Suppresses pending completion; an already locked canvas may still post.
     * Keep the Surface alive until close()'s cleanup callback has run.
     */
    public void cancel() {
        requireMain();
        if (!closed) generation.incrementAndGet();
    }

    /** Release caller Surface only from onReleased, after the worker is done. */
    public void close(Runnable onReleased) {
        requireMain();
        if (closed) throw new IllegalStateException("Renderer already disposed");
        closed = true; generation.incrementAndGet();
        worker.post(() -> {
            if (bitmap != null) { bitmap.recycle(); bitmap = null; }
            argb = null;
            thread.quitSafely();
            if (onReleased != null) main.post(onReleased);
        });
    }

    @Override public void close() { close(null); }
    private static void requireMain() {
        if (Looper.myLooper() != Looper.getMainLooper()) throw new IllegalStateException("Renderer lifecycle requires main thread");
    }
}
