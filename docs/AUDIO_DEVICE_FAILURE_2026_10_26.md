# User-reported acoustic failure — 2026-10-26

Status: OPEN, not fixed.

The user reports GGWave Audible selected on BOTH Samsung A24 and Samsung J7. Neither direction recognized the start announcement, even after waiting. This is user-reported physical testing, not an assistant-observed device run. Exact installed APK version, device OS versions, route, recorded PCM and sound levels have not yet been captured. The most recent APKs supplied in this conversation were 0.4.0; installation of that exact build is not independently confirmed.

This failure occurs before payload reconstruction; OFDM and the inflated duration estimate do not explain this particular Audible test. No root cause has been established. Candidate areas to measure are the actual output/input audio route, recorded signal level/silence/clipping, native decoder detections and forwarding of decoded announcements into Flutter. Do not label hardware eligibility as a working acoustic link.

Additional host check: compiled the existing production ggwave source with the existing PCM regression modified in scratch to feed 1024 samples per call (matching AudioBridge's maximum capture batch rather than the regression's 2048). Eight cases passed: payload sizes 73 and 132, audible-fast and ultrasound-fast, clean and deterministic low noise. The 73-byte waveform took 5.163 seconds; 132 bytes took 8.747 seconds. These use generated payloads, not a phone recording, and do not prove Android capture, acoustic propagation or actual start-message delivery.

Next diagnostic build should expose microphone PCM activity, signal level/clipping, active input/output route, decoder packet counts and whether a valid matching VDS3 announcement was parsed. It should distinguish no capture, undecodable signal, invalid/mismatched announcement and payload reconstruction. No blind gain/frequency increase or claimed fix is justified by current evidence.
