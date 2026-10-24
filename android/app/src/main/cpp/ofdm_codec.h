#pragma once
#include <cstdint>
#include <cstddef>
#include <vector>
namespace viadrop {
// Experimental audible OFDM: 16-QAM, rate 1/2, 1.1–16 kHz, 48 kHz PCM.
std::vector<int16_t> ofdmEncode(const std::vector<uint8_t>& data);
class OfdmReceiver {
 public:
  std::vector<uint8_t> feed(const int16_t* samples, size_t count);
 private:
  std::vector<float> samples_;
  size_t sinceDecode_ = 0;
};
}
