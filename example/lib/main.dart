import 'dart:async';
import 'dart:math';
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
      debugShowCheckedModeBanner: false,
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
            content: Text('Start Error: $e'),
            backgroundColor: Colors.red,
          ),
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

  String _extractDisplayName(String magnet) {
    try {
      final match = RegExp(r'[?&]dn=([^&]+)').firstMatch(magnet);
      if (match != null && match.group(1) != null) {
        return Uri.decodeComponent(match.group(1)!.replaceAll('+', ' '));
      }
    } catch (_) {}
    return '';
  }

  Future<void> _addTorrent() async {
    final magnet = _magnetController.text.trim();
    if (magnet.isEmpty) return;

    final displayName = _extractDisplayName(magnet);

    try {
      final added = await _controller.addTorrent(
        magnet: magnet,
        title: displayName,
        saveToDb: true,
      );

      _magnetController.clear();

      if (mounted) {
        final title = added.title.isNotEmpty
            ? added.title
            : (displayName.isNotEmpty ? displayName : added.hash);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added torrent: $title'),
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
            backgroundColor: Colors.red,
          ),
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
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatBytes(num bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    final index = i.clamp(0, suffixes.length - 1);
    final size = bytes / pow(1024, index);
    return '${size.toStringAsFixed(index == 0 ? 0 : 2)} ${suffixes[index]}';
  }

  void _showStreamUrlDialog(TorrentInfo torrent, [TorrentFileStat? file]) {
    final fileIndex = file?.id ??
        (torrent.fileStats.isNotEmpty ? torrent.fileStats.first.id : 1);
    final streamUrl = _controller.streamUrl(torrent.hash, fileIndex: fileIndex);
    final fileLabel = file != null
        ? file.path
        : (torrent.title.isNotEmpty ? torrent.title : torrent.hash);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.play_circle_fill, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Playable HTTP Stream URL',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'File #$fileIndex: $fileLabel',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
            if (file != null && file.length > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Size: ${_formatBytes(file.length)}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Use this direct stream URL in VLC, MPV, media_kit, or video_player:',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: SelectableText(
                streamUrl.toString(),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.lightGreenAccent,
                ),
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
                const SnackBar(
                  content: Text('Stream URL copied to clipboard!'),
                  backgroundColor: Colors.deepPurple,
                ),
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
      applicationVersion: '0.0.1',
      applicationLegalese:
          'TorrServer is licensed under GNU General Public License v3.0 (GPL-3.0).\n'
          'The iOS build statically embeds TorrServer and inherits GPLv3 source obligations.',
    );
  }

  IconData _getFileIcon(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.ts')) {
      return Icons.video_file;
    } else if (lower.endsWith('.mp3') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.m4a')) {
      return Icons.audio_file;
    } else if (lower.endsWith('.srt') ||
        lower.endsWith('.vtt') ||
        lower.endsWith('.ass') ||
        lower.endsWith('.sub')) {
      return Icons.subtitles;
    } else if (lower.endsWith('.iso') ||
        lower.endsWith('.img') ||
        lower.endsWith('.bin')) {
      return Icons.album;
    } else if (lower.endsWith('.zip') ||
        lower.endsWith('.rar') ||
        lower.endsWith('.7z') ||
        lower.endsWith('.tar') ||
        lower.endsWith('.gz')) {
      return Icons.folder_zip;
    }
    return Icons.insert_drive_file;
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
                        hintText: 'Paste magnet:?xt=urn:btih:...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addTorrent(),
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
                        final speedStr = _formatBytes(t.downloadSpeed);
                        final totalStr = _formatBytes(t.torrentSize);
                        final loadedStr = _formatBytes(t.loadedSize);
                        final progress = t.torrentSize > 0
                            ? (t.loadedSize / t.torrentSize).clamp(0.0, 1.0)
                            : 0.0;

                        final title = t.title.isNotEmpty ? t.title : t.hash;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            leading: Icon(
                              progress >= 1.0
                                  ? Icons.check_circle_outline
                                  : (t.downloadSpeed > 0
                                      ? Icons.downloading
                                      : Icons.folder),
                              color: progress >= 1.0
                                  ? Colors.green
                                  : (t.downloadSpeed > 0
                                      ? Colors.lightBlueAccent
                                      : Colors.white70),
                            ),
                            title: Text(
                              title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white12,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        t.statString,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Peers: ${t.activePeers}/${t.totalPeers}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '$speedStr/s',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.lightGreenAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.white10,
                                  valueColor: AlwaysStoppedAnimation(
                                    progress >= 1.0
                                        ? Colors.green
                                        : Colors.deepPurpleAccent,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$loadedStr / $totalStr (${(progress * 100).toStringAsFixed(1)}%) • ${t.fileStats.length} files',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white60),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.play_arrow,
                                      color: Colors.green),
                                  tooltip: 'Stream First File',
                                  onPressed: () => _showStreamUrlDialog(t),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent),
                                  tooltip: 'Remove Torrent',
                                  onPressed: () => _removeTorrent(t.hash),
                                ),
                              ],
                            ),
                            children: [
                              const Divider(height: 1),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Files in Torrent (${t.fileStats.length})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                              if (t.fileStats.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text(
                                    'Fetching file metadata from peers...',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        color: Colors.white54),
                                  ),
                                )
                              else
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: t.fileStats.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1, indent: 48),
                                  itemBuilder: (ctx, fileIdx) {
                                    final file = t.fileStats[fileIdx];
                                    final fileIcon = _getFileIcon(file.path);
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(fileIcon,
                                          size: 20,
                                          color: Colors.deepPurpleAccent),
                                      title: Text(
                                        file.path,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        'File #${file.id} • ${_formatBytes(file.length)}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white60),
                                      ),
                                      trailing: FilledButton.tonalIcon(
                                        icon: const Icon(Icons.play_arrow,
                                            size: 16),
                                        label: const Text('Stream'),
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                        ),
                                        onPressed: () =>
                                            _showStreamUrlDialog(t, file),
                                      ),
                                    );
                                  },
                                ),
                            ],
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
