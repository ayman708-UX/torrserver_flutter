import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'exceptions.dart';

/// Resolves the filesystem path to the native TorrServer binary on subprocess platforms.
class BinaryLocator {
  /// Locates the appropriate TorrServer executable for the current platform and architecture.
  ///
  /// Checks the `TORRSERVER_FLUTTER_LOCAL_BINARIES` environment variable first,
  /// followed by application bundle paths, app support directories, AppImage mount directories,
  /// and working directory.
  ///
  /// Ensures execution permissions (`chmod 755`) on Unix-based systems, copying to a writable
  /// cache directory if running from a read-only filesystem (e.g. AppImage / squashfs).
  static Future<String> locateBinary({String? customBinaryPath}) async {
    if (customBinaryPath != null && customBinaryPath.isNotEmpty) {
      final file = File(customBinaryPath);
      if (await file.exists()) {
        return await _ensureExecutable(file.path);
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
        return await _ensureExecutable(binary);
      }
    }

    // Check executable directory, AppImage environment, and application support paths
    final searchDirs = <Directory>[];

    // On Android, query nativeLibraryDir directly from the plugin MethodChannel
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('torrserver_flutter');
        final nativeDir =
            await channel.invokeMethod<String>('getNativeLibraryDir');
        if (nativeDir != null && nativeDir.isNotEmpty) {
          searchDirs.add(Directory(nativeDir));
        }
      } catch (_) {}
    }

    // On Linux AppImage, check $APPDIR
    final appDir = Platform.environment['APPDIR'];
    if (appDir != null && appDir.isNotEmpty) {
      searchDirs.add(Directory(p.join(appDir, 'lib')));
      searchDirs.add(Directory(p.join(appDir, 'usr', 'lib')));
      searchDirs.add(Directory(p.join(appDir, 'usr', 'bin')));
      searchDirs.add(Directory(p.join(appDir, 'bin')));
      searchDirs.add(Directory(appDir));
    }

    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      searchDirs.add(exeDir);
      searchDirs.add(Directory(p.join(exeDir.path, 'lib')));
      searchDirs.add(Directory(p.join(exeDir.path, '..', 'lib')));
      searchDirs.add(Directory(p.join(exeDir.path, 'torrserver')));
      searchDirs.add(Directory(p.join(exeDir.path, 'bin')));
      searchDirs.add(Directory(p.join(exeDir.path, 'data', 'flutter_assets')));
    } catch (_) {}

    try {
      final appSupport = await getApplicationSupportDirectory();
      searchDirs.add(appSupport);
      searchDirs.add(Directory(p.join(appSupport.path, 'torrserver_bin')));
      searchDirs.add(Directory(p.join(appSupport.path, 'torrserver')));
      searchDirs.add(Directory(p.join(appSupport.path, 'bin')));
    } catch (_) {}

    searchDirs.add(Directory.current);
    searchDirs.add(Directory(p.join(Directory.current.path, 'bin')));
    searchDirs.add(Directory(p.join(Directory.current.path, 'lib')));

    for (final dir in searchDirs) {
      if (await dir.exists()) {
        final binary = await _findInDirectory(dir);
        if (binary != null) {
          return await _ensureExecutable(binary);
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
        'torrserver-linux-arm64',
        'TorrServer-linux-arm64',
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
        (version.contains('x86') && !version.contains('x64'))) {
      return '386';
    }
    return 'amd64';
  }

  static Future<String> _ensureExecutable(String sourcePath) async {
    if (!Platform.isLinux && !Platform.isMacOS && !Platform.isAndroid) {
      return sourcePath;
    }

    try {
      final res = await Process.run('chmod', ['755', sourcePath]);
      if (res.exitCode == 0) {
        return sourcePath;
      }
    } catch (_) {}

    // Check if the file already has execute permissions (e.g. read-only mount)
    try {
      final stat = await File(sourcePath).stat();
      // Check if any execute bit is set (0111 octal = 73 decimal = 0x49)
      if ((stat.mode & 0x49) != 0) {
        return sourcePath;
      }
    } catch (_) {}

    // Fallback for read-only squashfs (AppImage) where chmod fails & lacks +x:
    // Copy binary to writable app support directory and make executable
    try {
      final appSupport = await getApplicationSupportDirectory();
      final binDir = Directory(p.join(appSupport.path, 'torrserver_bin'));
      if (!await binDir.exists()) {
        await binDir.create(recursive: true);
      }
      final targetFile = File(p.join(binDir.path, p.basename(sourcePath)));
      final sourceFile = File(sourcePath);

      if (!await targetFile.exists() ||
          (await targetFile.length()) != (await sourceFile.length())) {
        await sourceFile.copy(targetFile.path);
      }
      await Process.run('chmod', ['755', targetFile.path]);
      return targetFile.path;
    } catch (_) {
      return sourcePath;
    }
  }
}
