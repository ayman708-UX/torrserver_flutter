library torrserver_flutter;

import 'dart:io';
import 'src/torrserver_controller.dart';
import 'src/torrserver_controller_ios.dart';
import 'src/torrserver_controller_subprocess.dart';

export 'src/binary_locator.dart';
export 'src/exceptions.dart';
export 'src/models/torrent_info.dart';
export 'src/models/torrserver_settings.dart';
export 'src/port_finder.dart';
export 'src/rest_client.dart';
export 'src/torrserver_controller.dart';

/// Factory creating a platform-appropriate [TorrServerController] instance.
///
/// On iOS, returns an in-process FFI controller ([TorrServerControllerIos]).
/// On Windows, Linux, macOS, and Android, returns a subprocess controller ([TorrServerControllerSubprocess]).
TorrServerController createTorrServerController() {
  if (Platform.isIOS) {
    return TorrServerControllerIos();
  }
  return TorrServerControllerSubprocess();
}
