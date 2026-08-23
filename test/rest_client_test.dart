import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:torrserver_flutter/torrserver_flutter.dart';

void main() {
  group('TorrServerRestClient', () {
    test('echo returns server version string', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/echo') {
          return http.Response('MatriX.143', 200);
        }
        return http.Response('Not Found', 404);
      });

      final client = TorrServerRestClient(
        Uri.parse('http://127.0.0.1:8090'),
        client: mockClient,
      );

      final version = await client.echo();
      expect(version, 'MatriX.143');
    });

    test('addTorrent sends action: add and parses returned status', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/torrents' && request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['action'], 'add');
          expect(body['link'], 'magnet:?xt=urn:btih:ubuntu_hash');

          return http.Response(
            jsonEncode({
              'title': 'Ubuntu Linux',
              'hash': 'ubuntu_hash',
              'stat': 0,
              'stat_string': 'Torrent added',
            }),
            200,
          );
        }
        return http.Response('Error', 500);
      });

      final client = TorrServerRestClient(
        Uri.parse('http://127.0.0.1:8090'),
        client: mockClient,
      );

      final torrent = await client.addTorrent(
        link: 'magnet:?xt=urn:btih:ubuntu_hash',
        title: 'Ubuntu Linux',
      );

      expect(torrent.title, 'Ubuntu Linux');
      expect(torrent.hash, 'ubuntu_hash');
      expect(torrent.stat, TorrentStat.added);
    });

    test('listTorrents returns list of torrents', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/torrents') {
          return http.Response(
            jsonEncode([
              {
                'title': 'Movie A',
                'hash': 'hash_a',
                'stat': 3,
                'stat_string': 'Torrent working',
              },
              {
                'title': 'Movie B',
                'hash': 'hash_b',
                'stat': 1,
                'stat_string': 'Torrent getting info',
              }
            ]),
            200,
          );
        }
        return http.Response('Error', 500);
      });

      final client = TorrServerRestClient(
        Uri.parse('http://127.0.0.1:8090'),
        client: mockClient,
      );

      final torrents = await client.listTorrents();
      expect(torrents.length, 2);
      expect(torrents[0].title, 'Movie A');
      expect(torrents[1].title, 'Movie B');
    });

    test('getTorrent returns specific torrent status', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/torrents') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['action'] == 'get' && body['hash'] == 'my_hash') {
            return http.Response(
              jsonEncode({
                'title': 'Found Torrent',
                'hash': 'my_hash',
                'stat': 3,
              }),
              200,
            );
          }
        }
        return http.Response('Not Found', 404);
      });

      final client = TorrServerRestClient(
        Uri.parse('http://127.0.0.1:8090'),
        client: mockClient,
      );

      final torrent = await client.getTorrent('my_hash');
      expect(torrent.title, 'Found Torrent');
      expect(torrent.hash, 'my_hash');
    });

    test('removeTorrent, dropTorrent, and setTorrent send proper actions',
        () async {
      final actions = <String>[];
      final mockClient = MockClient((request) async {
        if (request.url.path == '/torrents') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          actions.add(body['action'] as String);
          return http.Response('', 200);
        }
        return http.Response('Error', 500);
      });

      final client = TorrServerRestClient(
        Uri.parse('http://127.0.0.1:8090'),
        client: mockClient,
      );

      await client.removeTorrent('hash1');
      await client.dropTorrent('hash2');
      await client.setTorrent('hash3', title: 'New Title');

      expect(actions, ['rem', 'drop', 'set']);
    });

    test('getSettings and setSettings interact with /settings properly',
        () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/settings') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['action'] == 'get') {
            return http.Response(
              jsonEncode(const TorrServerSettings().toJson()),
              200,
            );
          } else if (body['action'] == 'set') {
            return http.Response('', 200);
          }
        }
        return http.Response('Error', 500);
      });

      final client = TorrServerRestClient(
        Uri.parse('http://127.0.0.1:8090'),
        client: mockClient,
      );

      final settings = await client.getSettings();
      expect(settings.cacheSize, 64 * 1024 * 1024);

      await client.setSettings(settings.copyWith(cacheSize: 100 * 1024 * 1024));
    });

    test('streamUrl constructs correct playable video URL', () {
      final client = TorrServerRestClient(
        Uri.parse('http://127.0.0.1:8090'),
      );

      final url = client.streamUrl('ubuntu_hash', fileIndex: 1);
      expect(
        url.toString(),
        'http://127.0.0.1:8090/stream?link=ubuntu_hash&index=1&play',
      );

      final defaultUrl = client.streamUrl('ubuntu_hash');
      expect(
        defaultUrl.toString(),
        'http://127.0.0.1:8090/stream?link=ubuntu_hash&index=1&play',
      );
    });

    test('HTTP failure throws typed TorrServerHttpException', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final client = TorrServerRestClient(
        Uri.parse('http://127.0.0.1:8090'),
        client: mockClient,
      );

      expect(
        () => client.getTorrent('non_existent'),
        throwsA(isA<TorrServerHttpException>()),
      );
    });
  });
}
