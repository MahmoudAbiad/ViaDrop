#include <cstddef>
#include "ofdm_codec.h"
extern "C" {
#include "cyrinx/cyrinx_bulk.h"
}
#include <algorithm>
#include <stdexcept>

namespace viadrop {
static const cyrinx_bulk_config config = {
  1100, 16000, 8, 4, "1/2", 8, 2048, 512, 48000, .5, 3.3, 2000, 14000
};
static cyrinx_bulk_geometry geometry() {
  cyrinx_bulk_geometry g{};
  if (cyrinx_bulk_compute_geometry(&config, &g) != 0 || g.payload_bytes != 1024)
    throw std::runtime_error("Invalid OFDM geometry");
  return g;
}
std::vector<int16_t> ofdmEncode(const std::vector<uint8_t>& data) {
  if (data.empty() || data.size() > 1018) throw std::runtime_error("OFDM packet size");
  auto g = geometry();
  std::vector<uint8_t> payload(g.payload_bytes, 0);
  payload[0]='V'; payload[1]='D'; payload[2]='F'; payload[3]='1';
  payload[4]=static_cast<uint8_t>(data.size() >> 8);
  payload[5]=static_cast<uint8_t>(data.size());
  std::copy(data.begin(), data.end(), payload.begin()+6);
  std::vector<float> wave(g.frame_samples);
  if(cyrinx_bulk_modulate(&config,payload.data(),payload.size(),wave.data(),wave.size(),nullptr)!=g.frame_samples)
    throw std::runtime_error("OFDM encode failed");
  std::vector<int16_t> pcm(wave.size());
  std::transform(wave.begin(),wave.end(),pcm.begin(),[](float x){
    return static_cast<int16_t>(std::clamp(x,-1.0f,1.0f)*32767);
  });
  return pcm;
}
std::vector<uint8_t> OfdmReceiver::feed(const int16_t* pcm, size_t count) {
  // Fixed allocation budget independent of transfer length. Each read is bounded.
  constexpr size_t maxSamples=65536, hop=16384;
  if(count>maxSamples) throw std::runtime_error("OFDM input size");
  if(samples_.size()+count>maxSamples)
    samples_.erase(samples_.begin(),samples_.begin()+(samples_.size()+count-maxSamples));
  for(size_t i=0;i<count;i++) samples_.push_back(pcm[i]/32768.0f);
  sinceDecode_+=count;
  const auto g=geometry();
  if(samples_.size()<static_cast<size_t>(g.frame_samples)+4096 || sinceDecode_<hop) return {};
  sinceDecode_=0;
  std::vector<uint8_t> payload(g.payload_bytes);
  int ok=0,total=0;
  auto n=cyrinx_bulk_demodulate(&config,samples_.data(),samples_.size(),payload.data(),payload.size(),&ok,&total,nullptr);
  // Do not release even partially CRC-valid payloads to the fountain decoder.
  if(n!=g.payload_bytes || total!=g.n_blocks || ok!=total) return {};
  if(payload[0]!='V'||payload[1]!='D'||payload[2]!='F'||payload[3]!='1') return {};
  size_t size=(static_cast<size_t>(payload[4])<<8)|payload[5];
  if(size==0||size>1018) return {};
  return {payload.begin()+6,payload.begin()+6+size};
}
}
