// SPDX-License-Identifier: MPL-2.0
// Copyright 2026 Mahmoud Abiad
package app.viadrop.color;
import android.graphics.ImageFormat;
import android.media.Image;
import android.os.Looper;

/** Owns and closes one acquired Android camera image on every return path.
 * Invoke synchronously on a bounded worker; the caller owns camera lifecycle
 * and must drop stale results after cancellation. No Image or plane is retained.
 */
public final class CameraImageDecoder {
    private CameraImageDecoder() {}
    public static byte[] decodeAndClose(Image image, int clockwiseDegrees,
                                        Yuv420Rgb.Matrix matrix) {
        if (image == null) return null;
        try {
            if (Looper.myLooper() == Looper.getMainLooper())
                throw new IllegalStateException("Camera decoding requires a worker");
            if (image.getFormat() != ImageFormat.YUV_420_888)
                throw new IllegalArgumentException("Unsupported camera pixel format");
            android.graphics.Rect crop = image.getCropRect();
            if (crop.left != 0 || crop.top != 0 || crop.right != image.getWidth() || crop.bottom != image.getHeight())
                throw new IllegalArgumentException("Cropped camera image requires explicit crop handling");
            Image.Plane[] p = image.getPlanes();
            if (p.length != 3) throw new IllegalArgumentException("Missing camera planes");
            Yuv420Rgb.Frame frame = Yuv420Rgb.convert(
                plane(p[0]), plane(p[1]), plane(p[2]), image.getWidth(), image.getHeight(),
                clockwiseDegrees, matrix);
            return ColorCodec.decode(frame.rgb, frame.width, frame.height, frame.width*3, false);
        } finally {
            image.close();
        }
    }
    private static Yuv420Rgb.Plane plane(Image.Plane p) {
        return new Yuv420Rgb.Plane(p.getBuffer(), p.getRowStride(), p.getPixelStride());
    }
}
