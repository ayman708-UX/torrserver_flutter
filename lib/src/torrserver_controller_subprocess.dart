import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'binary_locator.dart';
import 'exceptions.dart';
import 'models/torrent_info.dart';
import 'models/torrserver_settings.dart';
import 'port_finder.dart';
import 'rest_client.dart';
import 'torrserver_controller.dart';

/// Subprocess implementation of [TorrServerController] for Windows, Linux, macOS, and Android.
class TorrServerControllerSubprocess implements TorrServerController {
  Process? _process;
  int? _port;
  Uri? _baseUrl;
  TorrServerRestClient? _restClient;
  bool _isRunning = false;
  final List<String> _processLogs = [];

  @override
  bool get isRunning => _isRunning;

  @override
  Uri? get baseUrl => _baseUrl;

  @override
  int? get port => _port;

  /// Recent process stdout/stderr log output lines.
  List<String> get processLogs => List.unmodifiable(_processLogs);

  @override
  Future<void> start({
    int? port,
    TorrServerSettings? settings,
    Directory? dataDir,
    List<String>? extraArgs,
    String? customBinaryPath,
  }) async {
    if (_isRunning) {
      throw const TorrServerStartException('TorrServer is already running');
    }

    // 1. Locate native executable
    final binaryPath = await BinaryLocator.locateBinary(
      customBinaryPath: customBinaryPath,
    );

    // 2. Select free port
    final selectedPort = port ?? await PortFinder.findFreePort();

    // 3. Resolve database/config directory
    final resolvedDataDir = dataDir ?? await _getDefaultDataDir();
    if (!await resolvedDataDir.exists()) {
      await resolvedDataDir.create(recursive: true);
    }

    // 4. Construct CLI arguments
    final args = <String>[
      '-p',
      selectedPort.toString(),
      '-d',
      resolvedDataDir.path,
    ];

    if (extraArgs != null) {
      args.addAll(extraArgs);
    }

    _processLogs.clear();

    try {
      final process = await Process.start(
        binaryPath,
        args,
        mode: ProcessStartMode.normal,
      );

      _process = process;
      _port = selectedPort;
      _baseUrl = Uri.parse('http://127.0.0.1:$selectedPort');
      _restClient = TorrServerRestClient(_baseUrl!);

      // Listen to stdout and stderr
      process.stdout.transform(utf8.decoder).listen((data) {
        _logProcessOutput(data);
      });
      process.stderr.transform(utf8.decoder).listen((data) {
        _logProcessOutput(data);
      });

      // Listen for unexpected exit during startup
      unawaited(
        process.exitCode.then((code) {
          _isRunning = false;
          _process = null;
        }),
      );

      // 5. Poll healthcheck (/echo) with bounded timeout
      await _waitForServerReady(const Duration(seconds: 12));
      _isRunning = true;

      // 6. Apply initial settings if provided
      if (settings != null) {
        try {
          await _restClient!.setSettings(settings);
        } catch (_) {}
      }
    } catch (e) {
      await stop();
      if (e is TorrServerException) rethrow;
      throw TorrServerStartException(
        'Failed to start TorrServer subprocess: $e',
        e,
      );
    }
  }

  @override
  Future<void> stop() async {
    final process = _process;
    _isRunning = false;
    _baseUrl = null;
    _restClient?.close();
    _restClient = null;

    if (process == null) return;

    try {
      // Send graceful termination signal
      if (Platform.isWindows) {
        process.kill(ProcessSignal.sigkill);
      } else {
        process.kill(ProcessSignal.sigint);
      }

      // Await exit with 5s timeout, force-kill if needed
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } catch (_) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    } finally {
      _process = null;
      _port = null;
    }
  }

  @override
  Future<TorrentInfo> addTorrent({
    String? magnet,
    Uint8List? torrentFile,
    String? title,
    String? category,
    String? poster,
    String? data,
    bool saveToDb = false,
  }) async {
    _ensureRunning();
    if (magnet != null && magnet.isNotEmpty) {
      return _restClient!.addTorrent(
        link: magnet,
        title: title,
        category: category,
        poster: poster,
        data: data,
        saveToDb: saveToDb,
      );
    } else if (torrentFile != null && torrentFile.isNotEmpty) {
      return _restClient!.uploadTorrentFile(
        torrentBytes: torrentFile,
        title: title,
        category: category,
        poster: poster,
        data: data,
        saveToDb: saveToDb,
      );
    }
    throw const TorrServerInvalidTorrentException(
      'Either magnet URI or torrentFile bytes must be provided',
    );
  }

  @override
  Future<List<TorrentInfo>> listTorrents() {
    _ensureRunning();
    return _restClient!.listTorrents();
  }

  @override
  Future<TorrentInfo> getTorrent(String hash) {
    _ensureRunning();
    return _restClient!.getTorrent(hash);
  }

  @override
  Future<void> removeTorrent(String hash) {
    _ensureRunning();
    return _restClient!.removeTorrent(hash);
  }

  @override
  Future<void> dropTorrent(String hash) {
    _ensureRunning();
    return _restClient!.dropTorrent(hash);
  }

  @override
  Future<void> setTorrent(
    String hash, {
    String? title,
    String? poster,
    String? category,
    String? data,
  }) {
    _ensureRunning();
    return _restClient!.setTorrent(
      hash,
      title: title,
      poster: poster,
      category: category,
      data: data,
    );
  }

  @override
  Uri streamUrl(String hash, {int fileIndex = 0}) {
    _ensureRunning();
    return _restClient!.streamUrl(hash, fileIndex: fileIndex);
  }

  @override
  Future<TorrServerSettings> getSettings() {
    _ensureRunning();
    return _restClient!.getSettings();
  }

  @override
  Future<void> setSettings(TorrServerSettings settings) {
    _ensureRunning();
    return _restClient!.setSettings(settings);
  }

  @override
  Future<void> setDefaultSettings() {
    _ensureRunning();
    return _restClient!.setDefaultSettings();
  }

  @override
  Future<String> echo() {
    _ensureRunning();
    return _restClient!.echo();
  }

  void _ensureRunning() {
    if (!_isRunning || _restClient == null) {
      throw const TorrServerProcessException('TorrServer is not running');
    }
  }

  Future<void> _waitForServerReady(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_process == null) {
        throw TorrServerStartException(
          'TorrServer process exited prematurely during startup. Logs: ${_processLogs.join("\n")}',
        );
      }
      try {
        await _restClient!.echo(timeout: const Duration(milliseconds: 500));
        return; // Server responded!
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    throw TorrServerStartException(
      'TorrServer failed to respond to healthcheck within ${timeout.inSeconds} seconds. '
      'Logs: ${_processLogs.join("\n")}',
    );
  }

  void _logProcessOutput(String text) {
    final lines = text.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        _processLogs.add(trimmed);
        if (_processLogs.length > 200) {
          _processLogs.removeAt(0);
        }
      }
    }
  }

  Future<Directory> _getDefaultDataDir() async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      return Directory('${appSupport.path}/torrserver_data');
    } catch (_) {
      return Directory('${Directory.current.path}/torrserver_data');
    }
  }
}
