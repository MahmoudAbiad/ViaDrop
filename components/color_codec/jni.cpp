// SPDX-License-Identifier: MPL-2.0
// Copyright 2026 Mahmoud Abiad
#include <jni.h>
#include "codec.h"
#include <vector>
extern "C" JNIEXPORT jintArray JNICALL Java_app_viadrop_color_ColorCodec_dimensions(JNIEnv* e,jclass){
 int w=0,h=0;if(vd_color_dimensions(&w,&h)!=0)return nullptr;
 auto a=e->NewIntArray(2);if(!a)return nullptr;jint values[]={w,h};e->SetIntArrayRegion(a,0,2,values);return a;
}
extern "C" JNIEXPORT jbyteArray JNICALL Java_app_viadrop_color_ColorCodec_encode(JNIEnv* e,jclass,jbyteArray data){
 if(!data)return nullptr;
 try{
  int n=e->GetArrayLength(data);if(n<1||n>4096)return nullptr;
  int w=0,h=0;if(vd_color_dimensions(&w,&h)!=0)return nullptr;
  std::vector<uint8_t> input(n),rgb(static_cast<size_t>(w)*h*3);
  e->GetByteArrayRegion(data,0,n,reinterpret_cast<jbyte*>(input.data()));if(e->ExceptionCheck())return nullptr;
  size_t size=0;if(vd_color_encode(input.data(),n,rgb.data(),rgb.size(),&size)!=0)return nullptr;
  auto out=e->NewByteArray(size);if(!out)return nullptr;
  e->SetByteArrayRegion(out,0,size,reinterpret_cast<const jbyte*>(rgb.data()));return out;
 }catch(...){return nullptr;}
}
extern "C" JNIEXPORT jbyteArray JNICALL Java_app_viadrop_color_ColorCodec_decode(JNIEnv* e,jclass,jbyteArray data,jint w,jint h,jint stride,jboolean rectified){
 if(!data||w<1||h<1||w>4096||h>4096||static_cast<size_t>(w)*h>4000000||stride<w*3||stride>32768)return nullptr;
 try{
  const size_t required=static_cast<size_t>(stride)*h;
  // Bound the JNI copy independently from the native image dimension bound.
  if(required>16*1024*1024||static_cast<size_t>(e->GetArrayLength(data))<required)return nullptr;
  std::vector<uint8_t> rgb(required),packet(4096);
  e->GetByteArrayRegion(data,0,required,reinterpret_cast<jbyte*>(rgb.data()));if(e->ExceptionCheck())return nullptr;
  size_t size=0;if(vd_color_decode(rgb.data(),rgb.size(),w,h,stride,rectified?1:0,packet.data(),packet.size(),&size)!=0)return nullptr;
  auto out=e->NewByteArray(size);if(!out)return nullptr;
  e->SetByteArrayRegion(out,0,size,reinterpret_cast<const jbyte*>(packet.data()));return out;
 }catch(...){return nullptr;}
}
