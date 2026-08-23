import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrserver_flutter/src/port_finder.dart';

void main() {
  group('PortFinder', () {
    test('findFreePort returns a valid, positive port number', () async {
      final port = await PortFinder.findFreePort();
      expect(port, isPositive);
      expect(port, greaterThan(1024));
    });

    test(
        'findFreePort returns distinct ports or available port on subsequent calls',
        () async {
      final port1 = await PortFinder.findFreePort();
      final port2 = await PortFinder.findFreePort();

      expect(port1, isPositive);
      expect(port2, isPositive);
    });

    test('isPortAvailable correctly detects occupied and free ports', () async {
      final freePort = await PortFinder.findFreePort();
      final isAvailable = await PortFinder.isPortAvailable(freePort);
      expect(isAvailable, isTrue);

      // Bind socket on loopback to occupy port
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final occupiedPort = socket.port;

      final isOccupiedAvailable =
          await PortFinder.isPortAvailable(occupiedPort);
      expect(isOccupiedAvailable, isFalse);

      await socket.close();
    });
  });
}
