// SPDX-License-Identifier: MPL-2.0
// Copyright 2026 Mahmoud Abiad
package app.viadrop.color;
import java.nio.ByteBuffer;

/** YUV420 planes to packed RGB; no Android dependency, no retained camera image.
 * Caller must select the actual limited-range matrix and close Image/ImageProxy
 * after conversion. Full-range and unknown color spaces are not inferred here.
 */
public final class Yuv420Rgb {
    private Yuv420Rgb() {}
    public enum Matrix { BT601_LIMITED, BT709_LIMITED }
    public static final class Plane {
        final ByteBuffer bytes;
        final int rowStride, pixelStride;
        public Plane(ByteBuffer bytes, int rowStride, int pixelStride) {
            if (bytes == null || rowStride <= 0 || rowStride > 32768 ||
                    pixelStride <= 0 || pixelStride > 4) throw new IllegalArgumentException("Plane layout");
            this.bytes = bytes.asReadOnlyBuffer();
            this.rowStride = rowStride;
            this.pixelStride = pixelStride;
        }
        void validate(int width, int height) {
            long row = (long)(width-1)*pixelStride+1;
            long required = (long)(height-1)*rowStride+row;
            if (row > rowStride || required > 16*1024*1024 || required > bytes.remaining())
                throw new IllegalArgumentException("Truncated plane");
        }
        int sample(int x,int y) {
            return bytes.get(bytes.position()+y*rowStride+x*pixelStride)&255;
        }
    }
    public static final class Frame {
        public final int width, height;
        public final byte[] rgb;
        Frame(int width,int height,byte[] rgb) {this.width=width;this.height=height;this.rgb=rgb;}
    }
    public static Frame convert(Plane y,Plane u,Plane v,int width,int height,
                                int clockwiseDegrees,Matrix matrix) {
        if (y==null||u==null||v==null||matrix==null||width<1||height<1||
            width>4096||height>4096||(long)width*height>4000000||
            (clockwiseDegrees!=0&&clockwiseDegrees!=90&&clockwiseDegrees!=180&&clockwiseDegrees!=270))
            throw new IllegalArgumentException("Frame geometry");
        y.validate(width,height);u.validate((width+1)/2,(height+1)/2);v.validate((width+1)/2,(height+1)/2);
        int outWidth=clockwiseDegrees%180==0?width:height;
        int outHeight=clockwiseDegrees%180==0?height:width;
        byte[] rgb=new byte[width*height*3];
        boolean bt709=matrix==Matrix.BT709_LIMITED;
        for(int row=0;row<height;row++)for(int col=0;col<width;col++) {
            int c=Math.max(0,y.sample(col,row)-16),d=u.sample(col/2,row/2)-128,e=v.sample(col/2,row/2)-128;
            int r=(298*c+(bt709?459:409)*e+128)>>8;
            int g=(298*c-(bt709?55:100)*d-(bt709?136:208)*e+128)>>8;
            int b=(298*c+(bt709?541:516)*d+128)>>8;
            int x=col,z=row;
            switch(clockwiseDegrees) {
                case 90: x=height-1-row;z=col;break;
                case 180: x=width-1-col;z=height-1-row;break;
                case 270: x=row;z=width-1-col;break;
                default: break;
            }
            int offset=(z*outWidth+x)*3;
            rgb[offset]=(byte)Math.max(0,Math.min(255,r));
            rgb[offset+1]=(byte)Math.max(0,Math.min(255,g));
            rgb[offset+2]=(byte)Math.max(0,Math.min(255,b));
        }
        return new Frame(outWidth,outHeight,rgb);
    }
}
