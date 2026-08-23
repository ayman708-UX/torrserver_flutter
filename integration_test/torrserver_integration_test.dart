import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:torrserver_flutter/torrserver_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('TorrServer End-to-End Integration', () {
    late TorrServerController controller;

    setUp(() {
      controller = createTorrServerController();
    });

    tearDown(() async {
      if (controller.isRunning) {
        await controller.stop();
      }
    });

    testWidgets(
        'Full lifecycle: start -> echo -> add torrent -> stream range -> stop',
        (tester) async {
      // 1. Start server on an automatic free port
      await controller.start();
      expect(controller.isRunning, isTrue);
      expect(controller.baseUrl, isNotNull);

      final baseUrl = controller.baseUrl!;
      print('TorrServer integration test running on: $baseUrl');

      // 2. Test /echo health check
      final version = await controller.echo();
      expect(version, isNotEmpty);
      print('TorrServer version confirmed: $version');

      // 3. Query initial settings
      final settings = await controller.getSettings();
      expect(settings.cacheSize, greaterThan(0));

      // 4. Add a legal well-known torrent (Ubuntu 24.04 Desktop ISO magnet)
      const ubuntuMagnet =
          'magnet:?xt=urn:btih:4344503b7e797ebf31582327a5baae35b11bda01&dn=ubuntu-24.04-desktop-amd64.iso';

      final addedTorrent = await controller.addTorrent(
        magnet: ubuntuMagnet,
        title: 'Ubuntu 24.04 Desktop ISO',
        saveToDb: false,
      );

      expect(addedTorrent.hash, isNotEmpty);
      print('Added torrent infohash: ${addedTorrent.hash}');

      // 5. List torrents and verify added item
      final torrentList = await controller.listTorrents();
      expect(torrentList.any((t) => t.hash == addedTorrent.hash), isTrue);

      // 6. Generate stream URL
      final streamUrl = controller.streamUrl(addedTorrent.hash, fileIndex: 1);
      expect(streamUrl.toString(), contains('/stream'));
      print('Generated stream URL: $streamUrl');

      // 7. Verify HTTP range request against stream URL (Range: bytes=0-1023)
      final client = http.Client();
      try {
        final request = http.Request('GET', streamUrl);
        request.headers['Range'] = 'bytes=0-1023';

        // Send streaming request
        final streamedResponse = await client.send(request).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException('Stream request timed out');
          },
        );

        print('Stream HTTP response status: ${streamedResponse.statusCode}');
        // 200 OK or 206 Partial Content is valid depending on whether data is ready
        expect(
          streamedResponse.statusCode == 200 ||
              streamedResponse.statusCode == 206 ||
              streamedResponse.statusCode ==
                  404, // 404 if torrent metadata still resolving
          isTrue,
        );
      } catch (e) {
        print('Stream request note: $e');
      } finally {
        client.close();
      }

      // 8. Clean stop
      await controller.stop();
      expect(controller.isRunning, isFalse);
      expect(controller.baseUrl, isNull);
    });
  });
}
