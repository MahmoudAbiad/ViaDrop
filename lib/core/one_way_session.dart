import 'dart:convert';
import 'dart:typed_data';

import 'physical_profiles.dart';
import 'vault.dart';

/// One-way start: session id + random secret + explicit transport profile.
/// Both phones must use the exact same implemented profile. No reply channel.
///
/// VDS3 deliberately rejects older VDS2 packets to avoid silent codec
/// mismatches. The shared secret is public to everyone who captures the start.
class OneWaySession {
  const OneWaySession._(this.sessionId, this.passphrase, this.profileId);

  static const String prefix = 'VDS3:';
  final int sessionId;
  final String passphrase;
  final String profileId;

  String get announcement =>
      '$prefix${sessionId.toRadixString(16).padLeft(8, '0')}:$passphrase:$profileId';

  Uint8List get audioAnnouncement =>
      Uint8List.fromList(utf8.encode(announcement));

  static OneWaySession create({String profileId = 'qr-standard'}) {
    final profile = physicalProfileById(profileId);
    if (profile == null || !profile.implemented) {
      throw ArgumentError.value(profileId, 'profileId', 'Unknown or unavailable profile');
    }
    final id = ByteData.sublistView(Vault.random(4)).getUint32(0) | 1;
    final secret = base64UrlEncode(Vault.random(32)).replaceAll('=', '');
    return OneWaySession._(id, secret, profileId);
  }

  static OneWaySession? parse(String value) {
    if (!value.startsWith(prefix)) return null;
    final fields = value.substring(prefix.length).split(':');
    if (fields.length != 3 ||
        !RegExp(r'^[0-9a-f]{8}$').hasMatch(fields[0]) ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(fields[1])) {
      return null;
    }
    final id = int.tryParse(fields[0], radix: 16);
    if (id == null || id == 0) return null;
    final profile = physicalProfileById(fields[2]);
    if (profile == null || !profile.implemented) return null;
    try {
      if (base64Url.decode(base64Url.normalize(fields[1])).length != 32) {
        return null;
      }
    } on FormatException {
      return null;
    }
    return OneWaySession._(id, fields[1], profile.id);
  }
}
