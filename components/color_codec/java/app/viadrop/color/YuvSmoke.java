// SPDX-License-Identifier: MPL-2.0
package app.viadrop.color;
import java.nio.ByteBuffer;
import java.util.Arrays;
public final class YuvSmoke {
    static void check(boolean condition){if(!condition)throw new AssertionError("YUV conversion");}
    static Yuv420Rgb.Plane plane(byte[] bytes,int row,int pixel){return new Yuv420Rgb.Plane(ByteBuffer.wrap(bytes),row,pixel);}
    static void rejects(Runnable r){try{r.run();}catch(IllegalArgumentException e){return;}throw new AssertionError("Invalid YUV accepted");}
    public static void main(String[] args){
        ByteBuffer luminance=ByteBuffer.wrap(new byte[]{99,16,82,77,(byte)145,(byte)235});luminance.position(1);
        Yuv420Rgb.Plane y=new Yuv420Rgb.Plane(luminance,3,1);
        // Chrominance may be interleaved, and the final plane row need not
        // contain its trailing row padding in Android camera buffers.
        Yuv420Rgb.Plane u=plane(new byte[]{(byte)128},2,2),v=plane(new byte[]{(byte)128},2,2);
        Yuv420Rgb.Frame plain=Yuv420Rgb.convert(y,u,v,2,2,0,Yuv420Rgb.Matrix.BT601_LIMITED);
        check(luminance.position()==1&&plain.width==2&&plain.height==2);
        int[] expected={0,77,150,255};
        for(int i=0;i<4;i++)for(int c=0;c<3;c++)check((plain.rgb[i*3+c]&255)==expected[i]);
        for(int angle:new int[]{90,180,270}){
            Yuv420Rgb.Frame frame=Yuv420Rgb.convert(y,u,v,2,2,angle,Yuv420Rgb.Matrix.BT601_LIMITED);
            int[][] order={{2,0,3,1},{3,2,1,0},{1,3,0,2}};
            for(int i=0;i<4;i++)check((frame.rgb[i*3]&255)==expected[order[angle/90-1][i]]);
        }
        for(Yuv420Rgb.Matrix matrix:Yuv420Rgb.Matrix.values()){
            Yuv420Rgb.Frame red=Yuv420Rgb.convert(plane(new byte[]{82},1,1),plane(new byte[]{90},1,1),plane(new byte[]{(byte)240},1,1),1,1,0,matrix);
            check((red.rgb[0]&255)>240&&(red.rgb[1]&255)<35&&(red.rgb[2]&255)<10);
        }
        rejects(()->Yuv420Rgb.convert(y,u,v,4096,4096,0,Yuv420Rgb.Matrix.BT601_LIMITED));
        rejects(()->Yuv420Rgb.convert(y,u,v,2,2,45,Yuv420Rgb.Matrix.BT601_LIMITED));
        rejects(()->Yuv420Rgb.convert(plane(new byte[]{16},2,1),u,v,2,2,0,Yuv420Rgb.Matrix.BT601_LIMITED));
        System.out.println("PASS YUV stride, offsets, rotations, matrices and truncated-plane checks");
    }
}
