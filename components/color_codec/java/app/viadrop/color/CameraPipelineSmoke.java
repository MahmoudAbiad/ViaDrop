// SPDX-License-Identifier: MPL-2.0
// Copyright 2026 Mahmoud Abiad
package app.viadrop.color;
import java.nio.ByteBuffer;
import java.util.Arrays;

/** Synthetic camera path, not a hardware/camera test. Uses actual encoded
 * color pixels, YUV420 chroma subsampling and native extraction/packet CRC.
 */
public final class CameraPipelineSmoke {
    private static int clamp(int value) { return Math.max(0, Math.min(255, value)); }
    private static Yuv420Rgb.Plane plane(byte[] bytes, int stride) {
        return new Yuv420Rgb.Plane(ByteBuffer.wrap(bytes), stride, 1);
    }
    private static Yuv420Rgb.Frame camera(byte[] rgb, int width, int height, Yuv420Rgb.Matrix matrix) {
        byte[] y = new byte[width*height], u = new byte[width*height/4], v = new byte[u.length];
        boolean bt709 = matrix == Yuv420Rgb.Matrix.BT709_LIMITED;
        for (int row=0; row<height; row++) for (int col=0; col<width; col++) {
            int i=(row*width+col)*3, r=rgb[i]&255, g=rgb[i+1]&255, b=rgb[i+2]&255;
            y[row*width+col]=(byte)clamp((((bt709?47:66)*r+(bt709?157:129)*g+(bt709?16:25)*b+128)>>8)+16);
        }
        for (int row=0; row<height; row+=2) for (int col=0; col<width; col+=2) {
            int r=0,g=0,b=0;
            for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++) {
                int i=((row+dy)*width+col+dx)*3;
                r+=rgb[i]&255;g+=rgb[i+1]&255;b+=rgb[i+2]&255;
            }
            r=(r+2)/4;g=(g+2)/4;b=(b+2)/4;
            int j=(row/2)*(width/2)+col/2;
            u[j]=(byte)clamp((((bt709?-26:-38)*r+(bt709?-87:-74)*g+112*b+128)>>8)+128);
            v[j]=(byte)clamp(((112*r+(bt709?-102:-94)*g+(bt709?-10:-18)*b+128)>>8)+128);
        }
        return Yuv420Rgb.convert(plane(y,width),plane(u,width/2),plane(v,width/2),width,height,0,matrix);
    }
    public static void main(String[] args) {
        byte[] payload=new byte[2432];
        for(int i=0;i<payload.length;i++)payload[i]=(byte)(i*71+i/7);
        byte[] rgb=ColorCodec.encode(payload);
        for(Yuv420Rgb.Matrix matrix:Yuv420Rgb.Matrix.values()) {
            Yuv420Rgb.Frame frame=camera(rgb,1024,1024,matrix);
            if(!Arrays.equals(payload,ColorCodec.decode(frame.rgb,frame.width,frame.height,frame.width*3,true)))
                throw new AssertionError("Color packet through YUV420 "+matrix);
            System.out.println("PASS synthetic encoded RGB -> YUV420 -> RGB -> native packet: "+matrix);
        }
        // A visible margin emulates a camera frame containing the entire screen
        // target rather than handing the decoder an already rectified image.
        byte[] scene=new byte[1280*1280*3];Arrays.fill(scene,(byte)255);
        for(int row=0;row<1024;row++)System.arraycopy(rgb,row*1024*3,scene,((row+128)*1280+128)*3,1024*3);
        Yuv420Rgb.Frame captured=camera(scene,1280,1280,Yuv420Rgb.Matrix.BT601_LIMITED);
        if(!Arrays.equals(payload,ColorCodec.decode(captured.rgb,1280,1280,1280*3,false)))
            throw new AssertionError("Synthetic camera extraction");
        System.out.println("PASS synthetic camera YUV420 and native unrectified extraction");
    }
}
