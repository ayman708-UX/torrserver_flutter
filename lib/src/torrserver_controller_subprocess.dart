import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
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
  AppLifecycleListener? _lifecycleListener;
  StreamSubscription<ProcessSignal>? _sigintSub;
  StreamSubscription<ProcessSignal>? _sigtermSub;
  Directory? _currentDataDir;

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

    // 2. Resolve database/config directory
    final resolvedDataDir = dataDir ?? await _getDefaultDataDir();
    if (!await resolvedDataDir.exists()) {
      await resolvedDataDir.create(recursive: true);
    }
    _currentDataDir = resolvedDataDir;

    // 3. Select free port & clean up potential orphaned instance / release BoltDB lock
    var selectedPort = port ?? await PortFinder.findFreePort();
    await _cleanupOrphans(resolvedDataDir, selectedPort);

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

      // Record PID for orphan tracking
      try {
        final pidFile = _getPidFile(resolvedDataDir);
        await pidFile.writeAsString(process.pid.toString());
      } catch (_) {}

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

      // 6. Setup automatic lifecycle listeners for cleanup on app close
      _setupLifecycleHooks();

      // 7. Apply initial settings if provided
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
    _disposeLifecycleHooks();
    final process = _process;
    final restClient = _restClient;
    final dataDir = _currentDataDir;

    _isRunning = false;
    _baseUrl = null;
    _process = null;
    _port = null;
    _restClient = null;

    // 1. Try graceful HTTP shutdown endpoint
    if (restClient != null) {
      try {
        await restClient.shutdown(timeout: const Duration(seconds: 1));
      } catch (_) {}
      restClient.close();
    }

    // 2. Terminate subprocess if still active
    if (process != null) {
      try {
        if (Platform.isWindows) {
          process.kill(ProcessSignal.sigkill);
        } else {
          process.kill(ProcessSignal.sigterm);
        }

        await process.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } catch (_) {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    }

    // 3. Clean up PID file
    if (dataDir != null) {
      try {
        final pidFile = _getPidFile(dataDir);
        if (await pidFile.exists()) {
          await pidFile.delete();
        }
      } catch (_) {}
    }
  }

  void _setupLifecycleHooks() {
    try {
      _lifecycleListener ??= AppLifecycleListener(
        onDetach: () {
          unawaited(stop());
        },
        onExitRequested: () async {
          await stop();
          return AppExitResponse.exit;
        },
        onHide: () {
          // On mobile / desktop minimize, keep running
        },
      );
    } catch (_) {}

    if (!Platform.isWindows && !Platform.isAndroid) {
      try {
        _sigintSub ??= ProcessSignal.sigint.watch().listen((_) {
          unawaited(stop());
        });
      } catch (_) {}
      try {
        _sigtermSub ??= ProcessSignal.sigterm.watch().listen((_) {
          unawaited(stop());
        });
      } catch (_) {}
    }
  }

  void _disposeLifecycleHooks() {
    try {
      _lifecycleListener?.dispose();
    } catch (_) {}
    _lifecycleListener = null;
    try {
      _sigintSub?.cancel();
    } catch (_) {}
    _sigintSub = null;
    try {
      _sigtermSub?.cancel();
    } catch (_) {}
    _sigtermSub = null;
  }

  File _getPidFile(Directory dataDir) =>
      File(p.join(dataDir.path, 'torrserver.pid'));

  Future<void> _cleanupOrphans(Directory dataDir, int targetPort) async {
    // 1. Check PID file and terminate previous orphaned process
    try {
      final pidFile = _getPidFile(dataDir);
      if (await pidFile.exists()) {
        final pidStr = (await pidFile.readAsString()).trim();
        final pid = int.tryParse(pidStr);
        if (pid != null && pid > 0) {
          try {
            Process.killPid(pid, ProcessSignal.sigterm);
            await Future<void>.delayed(const Duration(milliseconds: 150));
            Process.killPid(pid, ProcessSignal.sigkill);
          } catch (_) {}
        }
        await pidFile.delete().catchError((_) => pidFile);
      }
    } catch (_) {}

    // 2. Probe target port and common default port (8090) for lingering TorrServer instances
    final portsToCheck = {targetPort, 8090};
    for (final port in portsToCheck) {
      try {
        final probeClient = TorrServerRestClient(
          Uri.parse('http://127.0.0.1:$port'),
        );
        final echo = await probeClient.echo(
          timeout: const Duration(milliseconds: 300),
        );
        if (echo.isNotEmpty) {
          _logProcessOutput(
            'Shutting down lingering TorrServer on port $port ($echo)...',
          );
          await probeClient.shutdown(timeout: const Duration(seconds: 1));
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      } catch (_) {
        // Port is clear
      }
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
        final logsStr = _processLogs.join('\n');
        if (logsStr.contains('Error open bboltDB') ||
            logsStr.contains('timeout')) {
          throw TorrServerStartException(
            'TorrServer process exited during startup due to database lock contention (bboltDB timeout on config.db). '
            'Logs: $logsStr',
          );
        }
        throw TorrServerStartException(
          'TorrServer process exited prematurely during startup. Logs: $logsStr',
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
