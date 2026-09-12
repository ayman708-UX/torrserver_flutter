// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:torrserver_flutter/torrserver_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'TorrServer live engine starts, echoes, and connects to BT client',
      (tester) async {
    final controller = createTorrServerController();

    try {
      // 1. Start TorrServer in-process/subprocess engine
      stderr.writeln('[TEST] Starting TorrServer controller...');
      await controller.start();
      expect(controller.isRunning, isTrue);
      expect(controller.baseUrl, isNotNull);
      stderr.writeln('[TEST] TorrServer is running at ${controller.baseUrl}');

      // 2. Healthcheck /echo
      final echoVersion = await controller.echo();
      stderr.writeln('[TEST] TorrServer /echo version: $echoVersion');
      expect(echoVersion, isNotEmpty);

      // 3. Connect to BitTorrent Client: getSettings
      final settings = await controller.getSettings();
      stderr.writeln(
        '[TEST] BT Client Settings - CacheSize: ${settings.cacheSize}, ConnectionsLimit: ${settings.connectionsLimit}',
      );
      expect(settings.cacheSize, isPositive);

      // 4. Connect to BitTorrent Client: add a torrent (magnet) to initialize the torrent engine
      stderr.writeln('[TEST] Adding torrent to BT client engine...');
      const testMagnet =
          'magnet:?xt=urn:btih:4344503b7e797ebf31582327a5baae35b11bda01&dn=ubuntu-24.04-desktop-amd64.iso';
      final addedInfo = await controller.addTorrent(
        magnet: testMagnet,
        title: 'Ubuntu 24.04 ISO',
        saveToDb: false,
      );
      stderr.writeln(
        '[TEST] Added Torrent Hash: ${addedInfo.hash}, Title: ${addedInfo.title}, Stat: ${addedInfo.stat}',
      );
      expect(addedInfo.hash, isNotEmpty);

      // 5. Verify the BT client has the torrent registered in memory/db
      final torrentList = await controller.listTorrents();
      stderr.writeln(
          '[TEST] BT Client Active Torrents count: ${torrentList.length}');
      expect(torrentList, isNotEmpty);
      expect(
        torrentList
            .any((t) => t.hash.toLowerCase() == addedInfo.hash.toLowerCase()),
        isTrue,
      );

      // 6. Stop engine cleanly
      stderr.writeln('[TEST] Stopping TorrServer...');
      await controller.stop();
      expect(controller.isRunning, isFalse);
      stderr.writeln('[TEST] TorrServer stopped cleanly!');
    } catch (e, stack) {
      stderr.writeln('==============================================');
      stderr.writeln('[TEST FATAL ERROR] Integration test failed: $e');
      stderr.writeln('StackTrace:\n$stack');
      stderr.writeln('==============================================');
      rethrow;
    }
  });
}
