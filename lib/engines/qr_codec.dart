import 'dart:convert';
import 'dart:typed_data';

/// Base45 forces QR alphanumeric mode (instead of byte mode for base64url).
/// Each 2-byte group becomes 3 alphanumeric characters.
const _alphabet = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';
final _digits = {
  for (var i = 0; i < _alphabet.length; i++) _alphabet[i]: i,
};

String encodeQrFrame(Uint8List data) {
  final out = StringBuffer('VDQ2:');
  for (var i = 0; i < data.length; i += 2) {
    if (i + 1 < data.length) {
      final n = data[i] * 256 + data[i + 1];
      out.write(_alphabet[n % 45]);
      out.write(_alphabet[(n ~/ 45) % 45]);
      out.write(_alphabet[n ~/ (45 * 45)]);
    } else {
      final n = data[i];
      out.write(_alphabet[n % 45]);
      out.write(_alphabet[n ~/ 45]);
    }
  }
  return out.toString();
}

Uint8List? decodeQrFrame(String raw) {
  if (raw.startsWith('VDQR:')) {
    try {
      return base64Url.decode(base64Url.normalize(raw.substring(5)));
    } on FormatException {
      return null;
    }
  }
  if (!raw.startsWith('VDQ2:')) return null;
  final payload = raw.substring(5);
  if (payload.isEmpty || payload.length % 3 == 1) return null;
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < payload.length;) {
    final first = _digits[payload[i++]];
    final second = _digits[payload[i++]];
    if (first == null || second == null) return null;
    if (i < payload.length) {
      final third = _digits[payload[i++]];
      if (third == null) return null;
      final n = first + second * 45 + third * 2025;
      if (n > 0xffff) return null;
      out.addByte(n >> 8);
      out.addByte(n & 0xff);
    } else {
      final n = first + second * 45;
      if (n > 0xff) return null;
      out.addByte(n);
    }
  }
  return out.takeBytes();
}
