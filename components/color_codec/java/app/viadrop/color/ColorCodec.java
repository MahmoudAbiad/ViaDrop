// SPDX-License-Identifier: MPL-2.0
// Copyright 2026 Mahmoud Abiad
package app.viadrop.color;
/** Bounded synchronous native codec. Invoke on a worker, never the UI thread.
 * RGB is packed 8-bit R,G,B with explicit row stride; not an Android YUV plane.
 * null means invalid/undecodable input. No native state or file handles retained.
 */
public final class ColorCodec {
    static { System.loadLibrary("viadrop_color_jni"); }
    private ColorCodec() {}
    public static native int[] dimensions();
    public static native byte[] encode(byte[] packet);
    public static native byte[] decode(byte[] rgb, int width, int height,
                                     int rowStride, boolean rectified);
}
