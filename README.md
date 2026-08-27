# torrserver_flutter

A production-grade Flutter package that embeds and controls **TorrServer** (`github.com/YouROK/TorrServer`, Go, GPL-3.0) for streaming torrents via TorrServer's HTTP REST API across **Windows, Linux, macOS, Android, and iOS**.

---

## Features

- **Cross-Platform**: Seamless support across Windows, Linux, macOS, Android, and iOS.
- **Unified Public API**: Identical `TorrServerController` interface across all platforms — no `Platform.isIOS` checks in application code.
- **Dynamic Port Selection**: Pre-selects a guaranteed free port to avoid `Port already in use` crashes.
- **Subprocess & In-Process FFI**:
  - **Desktop (Windows, Linux, macOS) & Android**: Subprocess engine with graceful `SIGINT`/`kill` shutdown.
  - **iOS**: In-process embedded Go engine via `TorrServerKit.xcframework` and `dart:ffi`.
- **Typed REST Client**: Full typed models for torrent operations (`add`, `list`, `get`, `remove`, `drop`, `set`) and server settings (`BTSets`), verified against the live `/swagger` API.
- **Streaming URL Generator**: Generates video-player-ready `/stream` and `/play` URLs supporting HTTP byte-range requests (`206 Partial Content`) for instant seeking.
- **Android Background Playback**: Includes Kotlin `ForegroundService` with notification channel support for Android 8.0+ (Oreo) and above.
- **Automated Binary Distribution**: Native binaries downloaded and cached on first build from GitHub Releases with SHA-256 integrity verification and offline override.

---

## Architecture & Linking Model

| Platform | Execution Model | IPC / Communication | GPL-3.0 Posture |
|---|---|---|---|
| **Windows** | Subprocess | Loopback HTTP (`127.0.0.1:<port>`) | Mere aggregation |
| **Linux** | Subprocess | Loopback HTTP (`127.0.0.1:<port>`) | Mere aggregation |
| **macOS** | Subprocess | Loopback HTTP (`127.0.0.1:<port>`) | Mere aggregation |
| **Android** | Subprocess | Loopback HTTP (`127.0.0.1:<port>`) | Mere aggregation |
| **iOS** | In-process FFI (`TorrServerKit.xcframework`) | `dart:ffi` + Loopback HTTP | Derivative work (Combined binary) |

### GPL-3.0 License Disclosure & Compliance
TorrServer is licensed under **GNU General Public License v3.0 (GPL-3.0)**.
- On **Desktop and Android**, TorrServer runs as an external subprocess. Under FSF guidelines, this constitutes "mere aggregation" and does not obligate the calling Flutter app's source code.
- On **iOS**, the engine is statically linked into the application binary. Any Flutter application embedding this package on iOS inherits GPLv3 source-availability obligations for the combined work. See [`NOTICE.md`](NOTICE.md) and [`LICENSE-GPL3`](LICENSE-GPL3) for details.

### App Store Distribution Notice
> **Important Note for iOS Developers**: Apple has precedent rejecting BitTorrent/media-downloading apps under App Store Review Guideline 5.2.3 (Legal — Intellectual Property). This package can be compiled, tested on iOS Simulators, and sideloaded or distributed outside the App Store (e.g. TestFlight internal testing, AltStore/EU DMA marketplaces, enterprise distribution). Be advised that submission to the public Apple App Store may face review challenges.

---

## Installation

Add `torrserver_flutter` to your `pubspec.yaml`:

```yaml
dependencies:
  torrserver_flutter: ^1.0.0
```

### Air-Gapped / Offline Binaries
To build without downloading binaries during CMake/Gradle/CocoaPods phases, set the environment variable:
```bash
export TORRSERVER_FLUTTER_LOCAL_BINARIES="/path/to/prebuilt/binaries"
```

---

## Usage

### 1. Initialize & Start the Server

```dart
import 'package:torrserver_flutter/torrserver_flutter.dart';

final controller = createTorrServerController();

// Starts TorrServer on a free auto-selected port
await controller.start();

print('TorrServer running at: ${controller.baseUrl}');
```

### 2. Add a Torrent & Get Stream URL

```dart
// Add magnet link
final torrent = await controller.addTorrent(
  magnet: 'magnet:?xt=urn:btih:...',
  title: 'Big Buck Bunny',
);

print('Torrent infohash: ${torrent.hash}');

// Construct streaming URL for video player
final streamUrl = controller.streamUrl(torrent.hash, fileIndex: 1);
print('Playable HTTP Stream URL: $streamUrl');
```

### 3. List & Monitor Torrents

```dart
final torrents = await controller.listTorrents();
for (final t in torrents) {
  print('${t.title}: ${t.statString} (${t.downloadSpeed} B/s, peers: ${t.activePeers})');
}
```

### 4. Stop Server

```dart
await controller.stop();
print('Server stopped successfully');
```

---

## Platform Configuration & Permissions

### Android Configuration
Add the following to your host app's `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest ...>
    <!-- Internet & Network permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />

    <application
        ...
        android:extractNativeLibs="true">
    </application>
</manifest>
```

### iOS Configuration
Add local networking and App Transport Security (ATS) keys to `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
<key>NSLocalNetworkUsageDescription</key>
<string>TorrServer discovers local peers and streams media over local HTTP.</string>
```

### macOS Configuration
If your macOS app uses App Sandbox, add network client and server entitlements in `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
```

---

## License
 
This project is licensed under the [GNU General Public License v3.0](LICENSE).
