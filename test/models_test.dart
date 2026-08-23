import 'package:flutter_test/flutter_test.dart';
import 'package:torrserver_flutter/torrserver_flutter.dart';

void main() {
  group('TorrentInfo and TorrentFileStat', () {
    test('parses TorrentInfo from live TorrServer sample JSON', () {
      final sampleJson = {
        'title': 'Ubuntu 24.04 Desktop AMD64',
        'category': 'iso',
        'poster': 'https://example.com/poster.jpg',
        'data': 'custom_data',
        'timestamp': 1714000000,
        'name': 'ubuntu-24.04-desktop-amd64.iso',
        'hash': '4344503b7e797ebf31582327a5baae35b11bda01',
        'torrs_hash': '',
        'stat': 3,
        'stat_string': 'Torrent working',
        'loaded_size': 524288000,
        'torrent_size': 6000000000,
        'preloaded_bytes': 67108864,
        'preload_size': 67108864,
        'download_speed': 1048576.0,
        'upload_speed': 524288.0,
        'total_peers': 45,
        'pending_peers': 2,
        'active_peers': 20,
        'connected_seeders': 15,
        'half_open_peers': 1,
        'bytes_written': 524288000,
        'bytes_written_data': 524288000,
        'bytes_read': 104857600,
        'bytes_read_data': 104857600,
        'bytes_read_useful_data': 104857600,
        'chunks_written': 500,
        'chunks_read': 100,
        'chunks_read_useful': 100,
        'chunks_read_wasted': 0,
        'pieces_dirtied_good': 250,
        'pieces_dirtied_bad': 0,
        'duration_seconds': 120.5,
        'bit_rate': '10 Mbps',
        'file_stats': [
          {
            'id': 1,
            'path': 'ubuntu-24.04-desktop-amd64.iso',
            'length': 6000000000,
          }
        ]
      };

      final info = TorrentInfo.fromJson(sampleJson);

      expect(info.title, 'Ubuntu 24.04 Desktop AMD64');
      expect(info.hash, '4344503b7e797ebf31582327a5baae35b11bda01');
      expect(info.stat, TorrentStat.working);
      expect(info.statString, 'Torrent working');
      expect(info.downloadSpeed, 1048576.0);
      expect(info.activePeers, 20);
      expect(info.fileStats.length, 1);
      expect(info.fileStats.first.id, 1);
      expect(info.fileStats.first.path, 'ubuntu-24.04-desktop-amd64.iso');
      expect(info.fileStats.first.length, 6000000000);

      final encoded = info.toJson();
      expect(encoded['hash'], info.hash);
      expect(encoded['stat'], 3);
      expect(encoded['file_stats'], isA<List>());
    });

    test('TorrentStat enum mapping is robust to unknown values', () {
      expect(TorrentStat.fromInt(0), TorrentStat.added);
      expect(TorrentStat.fromInt(1), TorrentStat.gettingInfo);
      expect(TorrentStat.fromInt(2), TorrentStat.preload);
      expect(TorrentStat.fromInt(3), TorrentStat.working);
      expect(TorrentStat.fromInt(4), TorrentStat.closed);
      expect(TorrentStat.fromInt(5), TorrentStat.inDb);
      expect(TorrentStat.fromInt(99), TorrentStat.unknown);
      expect(TorrentStat.fromInt(null), TorrentStat.unknown);
    });
  });

  group('TorrServerSettings', () {
    test('defaults match build spec §1.4 exactly', () {
      const settings = TorrServerSettings();

      expect(settings.cacheSize, 64 * 1024 * 1024); // 64 MB
      expect(settings.preloadCache, 50); // 50%
      expect(settings.connectionsLimit, 25); // 25
      expect(settings.retrackersMode, 1); // 1
      expect(settings.torrentDisconnectTimeout, 30); // 30s
      expect(settings.readerReadAHead, 95); // 95%
      expect(settings.responsiveMode, true); // true
      expect(settings.showFSActiveTorr, true); // true
      expect(settings.storeSettingsInJson, true); // true
      expect(settings.enableLPD, true); // true
      expect(settings.lpdIPv6, false); // false
    });

    test('roundtrips JSON serialization properly', () {
      const original = TorrServerSettings(
        cacheSize: 128 * 1024 * 1024,
        connectionsLimit: 50,
        readerReadAHead: 80,
        preloadCache: 30,
        torrentsSavePath: '/downloads/torrents',
        useDisk: true,
        tmdbSettings: TMDBConfig(apiKey: 'secret_tmdb_key'),
        torznabUrls: [
          TorznabConfig(
              host: 'https://prowlarr.local',
              key: 'apikey123',
              name: 'Prowlarr'),
        ],
      );

      final json = original.toJson();
      final restored = TorrServerSettings.fromJson(json);

      expect(restored.cacheSize, 128 * 1024 * 1024);
      expect(restored.connectionsLimit, 50);
      expect(restored.readerReadAHead, 80);
      expect(restored.preloadCache, 30);
      expect(restored.useDisk, true);
      expect(restored.torrentsSavePath, '/downloads/torrents');
      expect(restored.tmdbSettings.apiKey, 'secret_tmdb_key');
      expect(restored.torznabUrls.length, 1);
      expect(restored.torznabUrls.first.name, 'Prowlarr');
    });
  });
}
