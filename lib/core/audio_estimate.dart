/// Planning estimate, not a measured device transfer rate or an upper bound.
/// Native PCM regression: a 132-byte packet takes 8.747 seconds at 48 kHz.
/// Add the engine's 180 ms gap, envelope allowance, and 25–100% fountain/loss
/// overhead. Pairing, retries and severe noise can take longer or never finish.
class AudioEstimate {
  const AudioEstimate(this.lowerMinutes, this.upperMinutes);
  final int lowerMinutes;
  final int upperMinutes;

  static AudioEstimate forInputBytes(int bytes, {bool fast = false}) {
    if (bytes < 0) throw ArgumentError.value(bytes, 'bytes');
    final block = fast ? 900 : 100;
    final frames = (bytes + 1024 + block - 1) ~/ block;
    final seconds = frames * ((fast ? 0.661334 : 8.747) + 0.180);
    return AudioEstimate((seconds * 1.25 / 60).ceil(),
        (seconds * 2 / 60).ceil());
  }
}
