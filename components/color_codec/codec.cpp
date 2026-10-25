// SPDX-License-Identifier: MPL-2.0
// Copyright 2026 Mahmoud Abiad
#include "codec.h"
#include "encoder/Encoder.h"
#include "encoder/Decoder.h"
#include "extractor/Extractor.h"
#include <cstring>
#include <sstream>
#include <string>
namespace {
constexpr size_t maxPacket=4096, header=12, maxPixels=4000000;
uint32_t crc(const uint8_t* data,size_t n){
 uint32_t value=0xffffffffu;
 for(size_t i=0;i<n;i++){value^=data[i];for(int bit=0;bit<8;bit++)value=(value>>1)^(0xedb88320u & (0u-(value&1u)));}
 return ~value;
}
void put(uint8_t* p,uint32_t v){for(int i=0;i<4;i++)p[i]=static_cast<uint8_t>(v>>(24-8*i));}
uint32_t get(const uint8_t* p){uint32_t v=0;for(int i=0;i<4;i++)v=(v<<8)|p[i];return v;}
void configure(){cimbar::Config::update(4);}
}
extern "C" int vd_color_dimensions(int* w,int* h){
 if(!w||!h)return -1;
 try{configure();*w=cimbar::Config::image_size_x();*h=cimbar::Config::image_size_y();return 0;}catch(...){return -3;}
}
extern "C" int vd_color_encode(const uint8_t* packet,size_t n,uint8_t* rgb,size_t cap,size_t* written){
 if(written)*written=0;
 if(!written||!packet||!rgb||n==0||n>maxPacket)return -1;
 try{
  configure();int w=0,h=0;if(vd_color_dimensions(&w,&h)!=0)return -3;
  const size_t required=static_cast<size_t>(w)*h*3;
  if(cap<required)return -2;
  std::string payload(header+n,'\0');auto p=reinterpret_cast<uint8_t*>(payload.data());
  std::memcpy(p,"VDCL",4);put(p+4,n);put(p+8,crc(packet,n));std::memcpy(p+header,packet,n);
  std::istringstream source(payload,std::ios::binary);Encoder encoder(4,2);
  auto image=encoder.encode_next(source);
  if(!image||image->type()!=CV_8UC3||image->cols!=w||image->rows!=h)return -3;
  for(int y=0;y<h;y++)std::memcpy(rgb+static_cast<size_t>(y)*w*3,image->ptr(y),static_cast<size_t>(w)*3);
  *written=required;return 0;
 }catch(...){return -3;}
}
extern "C" int vd_color_decode(const uint8_t* rgb,size_t n,int w,int h,size_t stride,int rectified,uint8_t* packet,size_t cap,size_t* written){
 if(written)*written=0;
 if(!written||!rgb||!packet||w<=0||h<=0||w>4096||h>4096||static_cast<size_t>(w)*h>maxPixels||
    stride<static_cast<size_t>(w)*3||stride>32768||n<stride*static_cast<size_t>(h)||
    (rectified!=0&&rectified!=1))return -1;
 try{
  configure();cv::Mat view(h,w,CV_8UC3,const_cast<uint8_t*>(rgb),stride),image;
  if(rectified){if(w!=static_cast<int>(cimbar::Config::image_size_x())||h!=static_cast<int>(cimbar::Config::image_size_y()))return -1;image=view;}
  else{Extractor extractor;if(extractor.extract(view,image)==Extractor::FAILURE)return -3;}
  std::ostringstream output(std::ios::binary);Decoder decoder;
  decoder.decode(image,output,false);const auto raw=output.str();
  if(raw.size()<header||raw.compare(0,4,"VDCL")!=0)return -3;
  auto p=reinterpret_cast<const uint8_t*>(raw.data());size_t size=get(p+4);
  if(size==0||size>maxPacket||size>raw.size()-header||crc(p+header,size)!=get(p+8))return -3;
  if(cap<size)return -2;
  std::memcpy(packet,p+header,size);*written=size;return 0;
 }catch(...){return -3;}
}
