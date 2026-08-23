import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'exceptions.dart';

typedef StartServerNative = Pointer<Utf8> Function(
    Int32 port, Pointer<Utf8> dataDir);
typedef StartServerDart = Pointer<Utf8> Function(
    int port, Pointer<Utf8> dataDir);

typedef StopServerNative = Pointer<Utf8> Function();
typedef StopServerDart = Pointer<Utf8> Function();

typedef IsRunningNative = Int32 Function();
typedef IsRunningDart = int Function();

/// Direct `dart:ffi` bindings to the statically linked `TorrServerKit` XCFramework on iOS.
class TorrServerIosBindings {
  late final DynamicLibrary _dylib;
  late final StartServerDart _startServer;
  late final StopServerDart _stopServer;
  late final IsRunningDart _isRunning;

  TorrServerIosBindings({DynamicLibrary? dynamicLibrary}) {
    if (dynamicLibrary != null) {
      _dylib = dynamicLibrary;
    } else {
      if (Platform.isIOS || Platform.isMacOS) {
        _dylib = DynamicLibrary.process();
      } else {
        throw const TorrServerFfiException(
            'TorrServer iOS bindings only supported on iOS / macOS');
      }
    }

    try {
      _startServer = _dylib
          .lookupFunction<StartServerNative, StartServerDart>('StartServer');
      _stopServer =
          _dylib.lookupFunction<StopServerNative, StopServerDart>('StopServer');
      _isRunning =
          _dylib.lookupFunction<IsRunningNative, IsRunningDart>('IsRunning');
    } catch (e) {
      throw TorrServerFfiException(
          'Failed to load TorrServer native symbols: $e', e);
    }
  }

  /// Starts the embedded TorrServer on the specified port and data directory.
  /// Returns null on success, or an error string on failure.
  String? startServer(int port, String dataDir) {
    final cDataDir = dataDir.toNativeUtf8();
    try {
      final resultPtr = _startServer(port, cDataDir);
      if (resultPtr == nullptr) {
        return null;
      }
      final errorMsg = resultPtr.toDartString();
      return errorMsg;
    } finally {
      calloc.free(cDataDir);
    }
  }

  /// Stops the embedded TorrServer.
  /// Returns null on success, or an error string on failure.
  String? stopServer() {
    final resultPtr = _stopServer();
    if (resultPtr == nullptr) {
      return null;
    }
    return resultPtr.toDartString();
  }

  /// Returns 1 if the embedded server is currently running, 0 otherwise.
  int isRunning() {
    return _isRunning();
  }
}
