import 'dart:convert';
import 'dart:typed_data';

import 'vault.dart';

/// Session invitation that travels in ONE direction (QR or acoustic start).
///
/// The invitation contains the session's random encryption secret. Anyone who
/// sees/hears it can decrypt the transfer; this is accidental-corruption
/// protection, NOT authenticated peer-to-peer confidentiality. There is no
/// listener reply, network discovery, or second QR scan.
class OneWaySession {
  const OneWaySession._(this.sessionId, this.passphrase);

  static const String prefix = 'VDS2:';
  final int sessionId;
  final String passphrase;

  String get announcement =>
      '$prefix${sessionId.toRadixString(16).padLeft(8, '0')}:$passphrase';

  Uint8List get audioAnnouncement =>
      Uint8List.fromList(utf8.encode(announcement));

  static OneWaySession create() {
    final id = ByteData.sublistView(Vault.random(4)).getUint32(0) | 1;
    final secret = base64UrlEncode(Vault.random(32)).replaceAll('=', '');
    return OneWaySession._(id, secret);
  }

  static OneWaySession? parse(String value) {
    if (!value.startsWith(prefix)) return null;
    final fields = value.substring(prefix.length).split(':');
    if (fields.length != 2 ||
        !RegExp(r'^[0-9a-f]{8}$').hasMatch(fields[0]) ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(fields[1])) {
      return null;
    }
    final id = int.tryParse(fields[0], radix: 16);
    if (id == null || id == 0) return null;
    try {
      if (base64Url.decode(base64Url.normalize(fields[1])).length != 32) {
        return null;
      }
    } on FormatException {
      return null;
    }
    return OneWaySession._(id, fields[1]);
  }
}
