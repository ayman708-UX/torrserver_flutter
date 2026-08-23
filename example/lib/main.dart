import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:torrserver_flutter/torrserver_flutter.dart';

void main() {
  runApp(const TorrServerExampleApp());
}

class TorrServerExampleApp extends StatelessWidget {
  const TorrServerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TorrServer Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const TorrServerHomePage(),
    );
  }
}

class TorrServerHomePage extends StatefulWidget {
  const TorrServerHomePage({super.key});

  @override
  State<TorrServerHomePage> createState() => _TorrServerHomePageState();
}

class _TorrServerHomePageState extends State<TorrServerHomePage> {
  final TorrServerController _controller = createTorrServerController();
  final TextEditingController _magnetController = TextEditingController(
    text:
        'magnet:?xt=urn:btih:4344503b7e797ebf31582327a5baae35b11bda01&dn=ubuntu-24.04-desktop-amd64.iso',
  );

  bool _isStarting = false;
  String _statusText = 'TorrServer stopped';
  String? _serverVersion;
  List<TorrentInfo> _torrents = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _magnetController.dispose();
    if (_controller.isRunning) {
      _controller.stop();
    }
    super.dispose();
  }

  Future<void> _startServer() async {
    setState(() {
      _isStarting = true;
      _statusText = 'Starting TorrServer...';
    });

    try {
      await _controller.start();
      final version = await _controller.echo();

      setState(() {
        _isStarting = false;
        _serverVersion = version;
        _statusText = 'Running at ${_controller.baseUrl} (TorrServer $version)';
      });

      _startAutoRefresh();
      await _refreshTorrents();
    } catch (e) {
      setState(() {
        _isStarting = false;
        _statusText = 'Error starting server: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Start Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _stopServer() async {
    _refreshTimer?.cancel();
    setState(() {
      _statusText = 'Stopping TorrServer...';
    });

    try {
      await _controller.stop();
      setState(() {
        _serverVersion = null;
        _torrents = [];
        _statusText = 'TorrServer stopped';
      });
    } catch (e) {
      setState(() {
        _statusText = 'Error stopping server: $e';
      });
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_controller.isRunning) {
        _refreshTorrents();
      }
    });
  }

  Future<void> _refreshTorrents() async {
    if (!_controller.isRunning) return;
    try {
      final list = await _controller.listTorrents();
      if (mounted) {
        setState(() {
          _torrents = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _addTorrent() async {
    final magnet = _magnetController.text.trim();
    if (magnet.isEmpty) return;

    try {
      final added = await _controller.addTorrent(
        magnet: magnet,
        title: 'Ubuntu 24.04 Desktop ISO',
        saveToDb: true,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Added torrent: ${added.title} (${added.hash.substring(0, 8)}...)'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _refreshTorrents();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to add torrent: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _removeTorrent(String hash) async {
    try {
      await _controller.removeTorrent(hash);
      await _refreshTorrents();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to remove: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showStreamUrlDialog(TorrentInfo torrent) {
    final streamUrl = _controller.streamUrl(torrent.hash, fileIndex: 1);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Playable HTTP Stream URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use this URL in video_player, media_kit, VLC, or MPV:',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            SelectableText(
              streamUrl.toString(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.lightGreenAccent,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy URL'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: streamUrl.toString()));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Stream URL copied to clipboard')),
              );
            },
          ),
          TextButton(
            child: const Text('Close'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  void _showLicensesDialog() {
    showLicensePage(
      context: context,
      applicationName: 'TorrServer Flutter Demo',
      applicationVersion: '1.0.0',
      applicationLegalese:
          'TorrServer is licensed under GNU General Public License v3.0 (GPL-3.0).\n'
          'The iOS build statically embeds TorrServer and inherits GPLv3 source obligations.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = _controller.isRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TorrServer Flutter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Open Source Licenses (GPL-3.0)',
            onPressed: _showLicensesDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isRunning ? Icons.check_circle : Icons.stop_circle,
                          color: isRunning ? Colors.green : Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusText,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
                          label:
                              Text(isRunning ? 'Stop Server' : 'Start Server'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isRunning
                                ? Colors.redAccent
                                : Colors.deepPurple,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _isStarting
                              ? null
                              : isRunning
                                  ? _stopServer
                                  : _startServer,
                        ),
                        const SizedBox(width: 12),
                        if (isRunning)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                            onPressed: _refreshTorrents,
                          ),
                        if (_serverVersion != null) ...[
                          const SizedBox(width: 12),
                          Chip(
                            label: Text('v$_serverVersion'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Magnet input
            if (isRunning) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _magnetController,
                      decoration: const InputDecoration(
                        labelText: 'Magnet Link or Torrent Hash',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                    onPressed: _addTorrent,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Torrent List Header
            Text(
              'Active Torrents (${_torrents.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),

            // Torrent List View
            Expanded(
              child: _torrents.isEmpty
                  ? Center(
                      child: Text(
                        isRunning
                            ? 'No active torrents. Add a magnet link above.'
                            : 'Start TorrServer to view and manage torrents.',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _torrents.length,
                      itemBuilder: (ctx, index) {
                        final t = _torrents[index];
                        final speedKb =
                            (t.downloadSpeed / 1024).toStringAsFixed(1);
                        final totalMb =
                            (t.torrentSize / (1024 * 1024)).toStringAsFixed(1);
                        final loadedMb =
                            (t.loadedSize / (1024 * 1024)).toStringAsFixed(1);

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(t.title.isNotEmpty ? t.title : t.hash),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  'Status: ${t.statString} | Peers: ${t.activePeers}/${t.totalPeers}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Speed: $speedKb KB/s | Downloaded: $loadedMb MB / $totalMb MB',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.play_circle_fill,
                                      color: Colors.green),
                                  tooltip: 'Get Stream URL',
                                  onPressed: () => _showStreamUrlDialog(t),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.redAccent),
                                  tooltip: 'Remove Torrent',
                                  onPressed: () => _removeTorrent(t.hash),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
