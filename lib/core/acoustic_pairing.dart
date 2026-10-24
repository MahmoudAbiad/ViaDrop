import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;
import 'qr_pairing.dart';

/// Acoustic handshake confirmation. No user-entered passphrase is necessary.
/// The token authenticates the receiver's ownership of the freshly derived
/// X25519 shared secret (unlike a plain, guessable session-number ACK).
class AcousticReady {
  static const prefix = 'VDREADY1:';

  static String token(OpticalPairing pairing) {
    final secret = pairing.passphrase;
    if (secret == null) throw StateError('Pairing not complete');
    final id = pairing.sessionId.toRadixString(16).padLeft(8, '0');
    final h = hashes.Hmac(hashes.sha256, utf8.encode(secret))
        .convert(utf8.encode('ViaDrop acoustic ready v1:' + id)).bytes;
    return prefix + id + ':' + base64UrlEncode(h.sublist(0, 12));
  }

  static bool verify(OpticalPairing pairing, String value) {
    final expected = token(pairing);
    final left = utf8.encode(value);
    final right = utf8.encode(expected);
    if (left.length != right.length) return false;
    var diff = 0;
    for (var i = 0; i < left.length; i++) {
      diff |= left[i] ^ right[i];
    }
    return diff == 0;
  }
}
