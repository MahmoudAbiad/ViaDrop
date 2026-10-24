import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:viadrop/core/transfer.dart';
import 'package:viadrop/core/vault.dart';
import 'package:viadrop/engines/lan.dart';

bool _privateIp(InternetAddress ip) {
  final parts = ip.rawAddress;
  if (parts.length != 4) return false;
  return parts[0] == 10 ||
      (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
      (parts[0] == 192 && parts[1] == 168);
}

void main() {
  test('LAN transfers a real encrypted file and receiver verifies it',
      () async {
    final hosts = await NetworkInterface.list(type: InternetAddressType.IPv4);
    final addresses = hosts.expand((i) => i.addresses).where(_privateIp);
    if (addresses.isEmpty) {
      // CI runners without a private IPv4 interface cannot exercise the LAN.
      // Device acceptance requires a separate two-phone test.
      return;
    }

    final local = addresses.first;
    final temporary = await Directory.systemTemp.createTemp('viadrop-lan-');
    LanEngine? receiver;
    LanEngine? sender;
    try {
      final socket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final port = socket.port;
      await socket.close();

      final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final discoveryPort = udp.port;
      udp.close();

      const password = 'an-adequately-long-shared-secret';
      final bytes = List<int>.generate(200003, (i) => (i * 17) % 256);
      final original = File(temporary.path + '/source.bin');
      await original.writeAsBytes(bytes);
      final encrypted = File(temporary.path + '/encrypted.vdp');
      await Vault.seal(original, encrypted, password, CancelToken());

      File? restored;
      var approved = false;
      final errors = <String>[];
      receiver = LanEngine(
        directory: temporary,
        port: port,
        discoveryPort: discoveryPort,
        consent: (name, size) async {
          approved = size == await encrypted.length();
          return approved;
        },
        onFile: (file) async {
          restored = await Vault.open(
            file,
            Directory(temporary.path + '/received'),
            password,
            CancelToken(),
          );
        },
        onProgress: (done, total) {},
        onError: (error) => errors.add(error.toString()),
      );
      await receiver.initialize();

      sender = LanEngine(
        directory: temporary,
        port: port,
        discoveryPort: discoveryPort,
        consent: (_, __) async => false,
        onFile: (_) async {},
        onProgress: (_, __) {},
        onError: (error) => errors.add(error.toString()),
      );
      var progress = 0;
      await sender
          .send(
            encrypted,
            Peer(local.address, 'test-receiver'),
            CancelToken(),
            (done, total) => progress = done,
          )
          .timeout(const Duration(seconds: 45));

      expect(approved, isTrue);
      expect(progress, await encrypted.length());
      expect(restored, isNotNull);
      expect(await restored!.readAsBytes(), orderedEquals(bytes));
      expect(errors, isEmpty);
    } finally {
      await sender?.dispose();
      await receiver?.dispose();
      await temporary.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('LAN startup releases TCP port if UDP discovery fails', () async {
    final temporary = await Directory.systemTemp.createTemp('viadrop-startup-');
    final reservation = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final tcpPort = reservation.port;
    await reservation.close();

    final engine = LanEngine(
      directory: temporary,
      port: tcpPort,
      discoveryPort: -1,
      consent: (peer, size) async => false,
      onFile: (file) async {},
      onProgress: (done, total) {},
      onError: (error) {},
    );
    try {
      await expectLater(engine.initialize(), throwsA(anything));
      // Without startup rollback, this bind fails with "address in use".
      final probe = await ServerSocket.bind(InternetAddress.anyIPv4, tcpPort);
      await probe.close();
    } finally {
      await engine.dispose();
      await temporary.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 20)));
}
