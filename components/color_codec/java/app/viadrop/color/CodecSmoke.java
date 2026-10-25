// SPDX-License-Identifier: MPL-2.0
package app.viadrop.color;
import java.util.Arrays;
public final class CodecSmoke {
    public static void main(String[] args) {
        int[] d = ColorCodec.dimensions();
        for (int size : new int[] {1, 100, 4096}) {
            byte[] data = new byte[size];
            for (int i=0; i<size; i++) data[i]=(byte)(i*71+i/7);
            byte[] image=ColorCodec.encode(data);
            byte[] result=ColorCodec.decode(image,d[0],d[1],d[0]*3,true);
            if (!Arrays.equals(data,result)) throw new AssertionError("JNI roundtrip");
        }
        if (ColorCodec.encode(new byte[4097])!=null || ColorCodec.encode(null)!=null ||
            ColorCodec.decode(new byte[1],Integer.MAX_VALUE,1,3,false)!=null ||
            ColorCodec.decode(new byte[1],1,1,3,false)!=null)
            throw new AssertionError("JNI input bound");
        System.out.println("PASS JNI RGB round trips and malformed input bounds");
    }
}
