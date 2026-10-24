#include <jni.h>
#include <vector>
#include "ggwave/ggwave.h"
extern "C" JNIEXPORT jlong JNICALL Java_app_viadrop_viadrop_MainActivity_waveInit(JNIEnv*,jobject){auto p=ggwave_getDefaultParameters();p.sampleRateInp=p.sampleRateOut=48000;p.sampleFormatInp=GGWAVE_SAMPLE_FORMAT_I16;p.sampleFormatOut=GGWAVE_SAMPLE_FORMAT_I16;return ggwave_init(p);}
extern "C" JNIEXPORT void JNICALL Java_app_viadrop_viadrop_MainActivity_waveFree(JNIEnv*,jobject,jlong h){ggwave_free((ggwave_Instance)h);}
extern "C" JNIEXPORT jbyteArray JNICALL Java_app_viadrop_viadrop_MainActivity_waveEncode(JNIEnv* e,jobject,jlong h,jbyteArray data,jboolean high){
 int len=e->GetArrayLength(data);if(len<=0||len>140)return nullptr;std::vector<jbyte>b(len);e->GetByteArrayRegion(data,0,len,b.data());
 auto mode=high?GGWAVE_PROTOCOL_ULTRASOUND_FAST:GGWAVE_PROTOCOL_AUDIBLE_FAST;int n=ggwave_encode((ggwave_Instance)h,b.data(),len,mode,20,nullptr,1);if(n<=0||n>4000000)return nullptr;
 std::vector<char>out(n);int actual=ggwave_encode((ggwave_Instance)h,b.data(),len,mode,20,out.data(),0);if(actual<=0||actual>n)return nullptr;
 auto r=e->NewByteArray(actual);e->SetByteArrayRegion(r,0,actual,(jbyte*)out.data());return r;
}
extern "C" JNIEXPORT jbyteArray JNICALL Java_app_viadrop_viadrop_MainActivity_waveDecode(JNIEnv* e,jobject,jlong h,jbyteArray pcm,jint n){
 if(n<=0||n>e->GetArrayLength(pcm))return nullptr;std::vector<jbyte>d(n);e->GetByteArrayRegion(pcm,0,n,d.data());char out[256];int len=ggwave_ndecode((ggwave_Instance)h,d.data(),n,out,256);if(len<=0||len>256)return nullptr;auto r=e->NewByteArray(len);e->SetByteArrayRegion(r,0,len,(jbyte*)out);return r;
}
