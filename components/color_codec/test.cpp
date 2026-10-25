// SPDX-License-Identifier: MPL-2.0
#include "codec.h"
#include <cstdio>
#include <stdexcept>
#include <vector>
void check(bool v){if(!v)throw std::runtime_error("color adapter assertion failed");}
int main(){
 int w=0,h=0;check(vd_color_dimensions(&w,&h)==0);check(w>0&&h>0);
 for(size_t size : {size_t(1),size_t(100),size_t(4096)}){
  std::vector<uint8_t> input(size),rgb(static_cast<size_t>(w)*h*3),out(4096);
  for(size_t i=0;i<size;i++)input[i]=(i*71+i/7)&255;
  size_t pixels=0,bytes=0;
  check(vd_color_encode(input.data(),size,rgb.data(),rgb.size(),&pixels)==0);
  check(vd_color_decode(rgb.data(),pixels,w,h,w*3,1,out.data(),out.size(),&bytes)==0);
  check(bytes==size);check(std::vector<uint8_t>(out.begin(),out.begin()+bytes)==input);
  bytes=99;check(vd_color_decode(rgb.data(),pixels-1,w,h,w*3,1,out.data(),out.size(),&bytes)==-1&&bytes==0);
  check(vd_color_encode(input.data(),size,rgb.data(),1,&pixels)==-2);
  // Camera rows often have extra padding; honor stride rather than reading
  // the padding bytes as pixel data.
  size_t stride=w*3+16;std::vector<uint8_t> padded(stride*h,123);
  for(int y=0;y<h;y++)for(int x=0;x<w*3;x++)padded[y*stride+x]=rgb[y*w*3+x];
  check(vd_color_decode(padded.data(),padded.size(),w,h,stride,1,out.data(),out.size(),&bytes)==0&&bytes==size);
  std::printf("PASS color adapter bytes=%zu RGB=%dx%d padded_stride\n",size,w,h);
 }
 std::vector<uint8_t> blank(static_cast<size_t>(w)*h*3,0),out(4096);size_t n=9;
 check(vd_color_decode(blank.data(),blank.size(),w,h,w*3,1,out.data(),out.size(),&n)!=0&&n==0);
 check(vd_color_decode(blank.data(),blank.size(),-1,h,w*3,1,out.data(),out.size(),&n)==-1);
 check(vd_color_encode(out.data(),4097,blank.data(),blank.size(),&n)==-1);
}
