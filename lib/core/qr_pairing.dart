import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';

import 'vault.dart';

/// Offline X25519 pairing, with no user-entered password.
///
/// Sender QR advertises its ephemeral public key; the receiver replies with a
/// second QR containing its ephemeral public key. Both derive a private AES
/// envelope passphrase. Nothing secret is shown in either QR.
class OpticalPairing {
  OpticalPairing._(this.sessionId, this._keyPair, this._localPublic, this._sender);

  static final X25519 _algorithm = X25519();
  static const invitePrefix = 'VDPAIR1:';
  static const replyPrefix = 'VDREPLY1:';

  final int sessionId;
  final KeyPair _keyPair;
  final List<int> _localPublic;
  final bool _sender;
  String? _secret;

  String? get passphrase => _secret;

  static Future<OpticalPairing> createSender() async {
    final id = ByteData.sublistView(Vault.random(4)).getUint32(0) | 1;
    final kp = await _algorithm.newKeyPair();
    final pk = await kp.extractPublicKey();
    return OpticalPairing._(id, kp, pk.bytes, true);
  }

  static Future<OpticalPairing?> acceptInvitation(String raw) async {
    final parsed = _parse(raw, invitePrefix);
    if (parsed == null) return null;
    final kp = await _algorithm.newKeyPair();
    final pk = await kp.extractPublicKey();
    final instance = OpticalPairing._(parsed.$1, kp, pk.bytes, false);
    try {
      await instance._derive(parsed.$2);
      return instance;
    } on Exception {
      return null;
    }
  }

  String get invitation {
    if (!_sender) throw StateError('Receiver cannot invite');
    return invitePrefix +
        sessionId.toRadixString(16).padLeft(8, '0') +
        ':' + base64UrlEncode(_localPublic);
  }

  String get reply {
    if (_sender || _secret == null) throw StateError('Receiver not paired');
    return replyPrefix +
        sessionId.toRadixString(16).padLeft(8, '0') +
        ':' + base64UrlEncode(_localPublic);
  }

  Future<bool> acceptReply(String raw) async {
    if (!_sender || _secret != null) return false;
    final parsed = _parse(raw, replyPrefix);
    if (parsed == null || parsed.$1 != sessionId) return false;
    try {
      await _derive(parsed.$2);
      return true;
    } on Exception {
      return false;
    }
  }

  Future<void> _derive(List<int> peerBytes) async {
    final peer = SimplePublicKey(peerBytes, type: KeyPairType.x25519);
    final shared = await _algorithm.sharedSecretKey(
      keyPair: _keyPair, remotePublicKey: peer,
    );
    final secretBytes = await shared.extractBytes();
    final idBytes = (ByteData(4)..setUint32(0, sessionId)).buffer.asUint8List();
    final senderBytes = _sender ? _localPublic : peerBytes;
    final receiverBytes = _sender ? peerBytes : _localPublic;
    final digest = hashes.sha256.convert([
      ...utf8.encode('ViaDrop optical pairing v1'),
      ...idBytes, ...senderBytes, ...receiverBytes, ...secretBytes,
    ]);
    _secret = base64UrlEncode(digest.bytes);
  }

  static (int, List<int>)? _parse(String raw, String prefix) {
    if (!raw.startsWith(prefix)) return null;
    final parts = raw.substring(prefix.length).split(':');
    if (parts.length != 2 || !RegExp(r'^[0-9a-f]{8}$').hasMatch(parts[0])) {
      return null;
    }
    final id = int.tryParse(parts[0], radix: 16);
    if (id == null || id == 0) return null;
    try {
      final bytes = base64Url.decode(base64Url.normalize(parts[1]));
      if (bytes.length != 32) return null;
      return (id, bytes);
    } on FormatException {
      return null;
    }
  }
}
