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

#include "ofdm_codec.h"
extern "C" JNIEXPORT jlong JNICALL Java_app_viadrop_viadrop_MainActivity_ofdmInit(JNIEnv*,jobject){
 try{return reinterpret_cast<jlong>(new viadrop::OfdmReceiver());}catch(...){return 0;}
}
extern "C" JNIEXPORT void JNICALL Java_app_viadrop_viadrop_MainActivity_ofdmFree(JNIEnv*,jobject,jlong h){delete reinterpret_cast<viadrop::OfdmReceiver*>(h);}
extern "C" JNIEXPORT jbyteArray JNICALL Java_app_viadrop_viadrop_MainActivity_ofdmEncode(JNIEnv* e,jobject,jbyteArray data){
 try {
  int n=e->GetArrayLength(data);if(n<=0||n>1018)return nullptr;
  std::vector<uint8_t> bytes(n);e->GetByteArrayRegion(data,0,n,reinterpret_cast<jbyte*>(bytes.data()));
  auto pcm=viadrop::ofdmEncode(bytes);std::vector<jbyte> wire(pcm.size()*2);
  for(size_t i=0;i<pcm.size();i++){wire[2*i]=pcm[i]&255;wire[2*i+1]=(static_cast<uint16_t>(pcm[i])>>8)&255;}
  auto result=e->NewByteArray(wire.size());e->SetByteArrayRegion(result,0,wire.size(),wire.data());return result;
 }catch(...){return nullptr;}
}
extern "C" JNIEXPORT jbyteArray JNICALL Java_app_viadrop_viadrop_MainActivity_ofdmDecode(JNIEnv* e,jobject,jlong h,jbyteArray data){
 if(!h)return nullptr;
 try {
  int n=e->GetArrayLength(data);if(n<=0||n>131072||n%2)return nullptr;
  std::vector<jbyte> wire(n);e->GetByteArrayRegion(data,0,n,wire.data());std::vector<int16_t> pcm(n/2);
  for(int i=0;i<n/2;i++)pcm[i]=static_cast<int16_t>(static_cast<uint8_t>(wire[2*i])|(static_cast<uint16_t>(static_cast<uint8_t>(wire[2*i+1]))<<8));
  auto bytes=reinterpret_cast<viadrop::OfdmReceiver*>(h)->feed(pcm.data(),pcm.size());
  if(bytes.empty())return nullptr;auto result=e->NewByteArray(bytes.size());
  e->SetByteArrayRegion(result,0,bytes.size(),reinterpret_cast<jbyte*>(bytes.data()));return result;
 }catch(...){return nullptr;}
}
