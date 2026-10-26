// Copyright 2026 Mahmoud Abiad. All rights reserved.
#pragma once
#include "ggwave/ggwave.h"
#include <mutex>

// ViaDrop transmits only these two GGWave protocols. Trying unrelated rates
// can accept a different decode of the same waveform before reaching FAST.
// GGWave's protocol defaults are global: configure once before any instance.
inline void configureViaDropWaveProtocols() {
    static std::once_flag configured;
    std::call_once(configured, [] {
        for (int id=0;id<GGWAVE_PROTOCOL_COUNT;++id)
            ggwave_rxToggleProtocol(static_cast<ggwave_ProtocolId>(id),
                id==GGWAVE_PROTOCOL_AUDIBLE_FAST || id==GGWAVE_PROTOCOL_ULTRASOUND_FAST);
    });
}
