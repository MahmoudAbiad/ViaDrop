#include "ofdm_codec.h"
#include <algorithm>
#include <cstdio>
#include <set>
#include <stdexcept>
#include <vector>
int main(){
 for(bool damaged : {false,true}){
  std::vector<int16_t> stream(3000,0);
  std::vector<std::vector<uint8_t>> packets;
  for(int id=0;id<4;id++){
   std::vector<uint8_t> p(932);for(size_t i=0;i<p.size();i++)p[i]=(i*71+id*23)&255;
   packets.push_back(p);auto wave=viadrop::ofdmEncode(p);
   stream.insert(stream.end(),wave.begin(),wave.end());stream.insert(stream.end(),8640,0);
  }
  stream.insert(stream.end(),65536,0);
  if(damaged){auto original=stream;unsigned rng=42;for(size_t i=0;i<stream.size();i++){
    rng=rng*1664525u+1013904223u;
    int v=original[i]+(i>=240?original[i-240]/5:0)+int((rng>>16)%65)-32;
    stream[i]=static_cast<int16_t>(std::clamp(v,-32768,32767));
  }}
  viadrop::OfdmReceiver rx;std::set<int> found;
  for(size_t i=0;i<stream.size();i+=1024){
   auto result=rx.feed(stream.data()+i,std::min<size_t>(1024,stream.size()-i));
   if(result.empty())continue;
   auto match=std::find(packets.begin(),packets.end(),result);
   if(match==packets.end())throw std::runtime_error("corrupt packet released");
   found.insert(static_cast<int>(match-packets.begin()));
  }
  std::printf("stream damaged=%d recovered=%zu/4\n",damaged,found.size());
  if(found.size()!=4)throw std::runtime_error("packet lost in PCM stream");
 }
}
