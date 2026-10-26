// Deterministic PCM simulation, not a speaker/microphone hardware test.
#include "ggwave/ggwave.h"
#include "../../android/app/src/main/cpp/wave_protocols.h"
#include <string>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <vector>

void roundTrip(int size, ggwave_ProtocolId mode, bool noisy) {
    configureViaDropWaveProtocols();
    auto p = ggwave_getDefaultParameters();
    p.sampleRateInp = p.sampleRateOut = 48000;
    p.sampleFormatInp = p.sampleFormatOut = GGWAVE_SAMPLE_FORMAT_I16;
    const auto tx = ggwave_init(p), rx = ggwave_init(p);
    if (tx < 0 || rx < 0) throw std::runtime_error("init failed");
    std::vector<uint8_t> data(size);
    for (int i = 0; i < size; ++i) data[i] = (i * 71 + 19) & 255;
    // The diagnostic probe is audible-only and has a fixed public payload.
    if (size == 8) { const char probe[]="VDPROBE1"; std::copy(probe,probe+8,data.begin()); }
    if(size==71){const std::string start="VDS3:00000001:"+std::string(43,'A')+":audio-audible";if(start.size()!=data.size())throw std::runtime_error("start fixture length");std::copy(start.begin(),start.end(),data.begin());}
    int n = ggwave_encode(tx, data.data(), size, mode, 20, nullptr, 1);
    if (n <= 0 || n > 4000000 || n % 2) throw std::runtime_error("invalid waveform");
    std::vector<int16_t> pcm(n / 2 + 48000, 0);
    int actual = ggwave_encode(tx, data.data(), size, mode, 20, pcm.data(), 0);
    if (actual != n) throw std::runtime_error("waveform length mismatch");
    if (noisy) {
        uint32_t state = 42;
        for (auto &sample : pcm) {
            state = state * 1664525u + 1013904223u;
            sample = static_cast<int16_t>(std::clamp(
                static_cast<int>(sample) + static_cast<int>((state >> 16) % 101) - 50,
                -32768, 32767));
        }
    }
    bool matched = false;
    for (size_t offset = 0; offset < pcm.size(); offset += 1024) {
        uint8_t decoded[256];
        int bytes = static_cast<int>(std::min<size_t>(1024, pcm.size() - offset) * 2);
        int count = ggwave_ndecode(rx, pcm.data() + offset, bytes, decoded, sizeof decoded);
        if (count > 0) {
            if (count != size || !std::equal(data.begin(), data.end(), decoded))
                throw std::runtime_error("decoded payload mismatch");
            matched = true;
        }
    }
    ggwave_free(tx); ggwave_free(rx);
    if (!matched) throw std::runtime_error("no decoded payload");
    std::printf("PASS bytes=%d mode=%d noise=%d waveform_seconds=%.3f\n",
                size, mode, noisy, n / 96000.0);
}
int main() {
    ggwave_setLogFile(nullptr);
    for (auto mode : {GGWAVE_PROTOCOL_AUDIBLE_FAST, GGWAVE_PROTOCOL_ULTRASOUND_FAST})
        for (int size : {8, 64, 71, 73, 132, 140})
            for (bool noisy : {false, true}) {
                if(size==8 && mode!=GGWAVE_PROTOCOL_AUDIBLE_FAST) continue;
                roundTrip(size, mode, noisy);
            }
}
