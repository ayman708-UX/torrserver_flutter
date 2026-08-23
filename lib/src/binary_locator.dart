import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'exceptions.dart';

/// Resolves the filesystem path to the native TorrServer binary on subprocess platforms.
class BinaryLocator {
  /// Locates the appropriate TorrServer executable for the current platform and architecture.
  ///
  /// Checks the `TORRSERVER_FLUTTER_LOCAL_BINARIES` environment variable first,
  /// followed by application bundle paths, app support directories, and working directory.
  ///
  /// Ensures execution permissions (`chmod 755`) on Unix-based systems.
  static Future<String> locateBinary({String? customBinaryPath}) async {
    if (customBinaryPath != null && customBinaryPath.isNotEmpty) {
      final file = File(customBinaryPath);
      if (await file.exists()) {
        await _ensureExecutable(file.path);
        return file.path;
      }
      throw TorrServerBinaryNotFoundException(
        'Custom TorrServer binary not found at specified path: $customBinaryPath',
        customBinaryPath,
      );
    }

    final overrideDir =
        Platform.environment['TORRSERVER_FLUTTER_LOCAL_BINARIES'];
    if (overrideDir != null && overrideDir.isNotEmpty) {
      final binary = await _findInDirectory(Directory(overrideDir));
      if (binary != null) {
        await _ensureExecutable(binary);
        return binary;
      }
    }

    // Check executable directory and application support paths
    final searchDirs = <Directory>[];

    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      searchDirs.add(exeDir);
      searchDirs.add(Directory(p.join(exeDir.path, 'data', 'flutter_assets')));
      searchDirs.add(Directory(p.join(exeDir.path, 'torrserver')));
      searchDirs.add(Directory(p.join(exeDir.path, 'bin')));
    } catch (_) {}

    try {
      final appSupport = await getApplicationSupportDirectory();
      searchDirs.add(appSupport);
      searchDirs.add(Directory(p.join(appSupport.path, 'torrserver')));
      searchDirs.add(Directory(p.join(appSupport.path, 'bin')));
    } catch (_) {}

    searchDirs.add(Directory.current);
    searchDirs.add(Directory(p.join(Directory.current.path, 'bin')));

    for (final dir in searchDirs) {
      if (await dir.exists()) {
        final binary = await _findInDirectory(dir);
        if (binary != null) {
          await _ensureExecutable(binary);
          return binary;
        }
      }
    }

    final platformName = Platform.operatingSystem;
    final arch = _getArchitecture();
    throw TorrServerBinaryNotFoundException(
      'Could not locate TorrServer executable for platform "$platformName" (arch: "$arch"). '
      'Ensure native binaries are downloaded or specify TORRSERVER_FLUTTER_LOCAL_BINARIES.',
    );
  }

  static Future<String?> _findInDirectory(Directory dir) async {
    final candidateNames = _getCandidateFilenames();
    for (final name in candidateNames) {
      final file = File(p.join(dir.path, name));
      if (await file.exists()) {
        return file.path;
      }
    }
    return null;
  }

  static List<String> _getCandidateFilenames() {
    final arch = _getArchitecture();
    if (Platform.isWindows) {
      return [
        'torrserver-windows-$arch.exe',
        'torrserver-windows-amd64.exe',
        'TorrServer-windows-$arch.exe',
        'TorrServer-windows-amd64.exe',
        'torrserver.exe',
        'TorrServer.exe',
      ];
    } else if (Platform.isLinux) {
      return [
        'torrserver-linux-$arch',
        'TorrServer-linux-$arch',
        'torrserver-linux-amd64',
        'TorrServer-linux-amd64',
        'torrserver',
        'TorrServer',
      ];
    } else if (Platform.isMacOS) {
      return [
        'torrserver-darwin-$arch',
        'TorrServer-darwin-$arch',
        'torrserver-darwin-arm64',
        'torrserver-darwin-amd64',
        'torrserver',
        'TorrServer',
      ];
    } else if (Platform.isAndroid) {
      return [
        'torrserver-android-$arch',
        'TorrServer-android-$arch',
        'torrserver-android-arm64',
        'torrserver-android-amd64',
        'torrserver-android-arm7',
        'torrserver-android-386',
        'libtorrserver.so',
        'torrserver',
        'TorrServer',
      ];
    }
    return ['torrserver', 'TorrServer'];
  }

  static String _getArchitecture() {
    final version = Platform.version.toLowerCase();
    if (version.contains('arm64') || version.contains('aarch64')) {
      return 'arm64';
    } else if (version.contains('armv7') || version.contains('arm7')) {
      return 'arm7';
    } else if (version.contains('ia32') ||
        version.contains('x86') && !version.contains('x64')) {
      return '386';
    }
    return 'amd64';
  }

  static Future<void> _ensureExecutable(String path) async {
    if (Platform.isLinux || Platform.isMacOS || Platform.isAndroid) {
      try {
        await Process.run('chmod', ['755', path]);
      } catch (_) {}
    }
  }
}
