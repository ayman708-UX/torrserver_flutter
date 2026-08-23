# Changelog

## 0.0.3

- Reduce release asset download sizes by ~75% (from ~58 MB to ~15 MB) via `.zip` and `.tar.gz` archive packaging.
- Fix Android runtime binary discovery by querying `nativeLibraryDir` via MethodChannel and setting `android:extractNativeLibs="true"`.
- Add 16 KB ELF page-size alignment (`-extldflags=-Wl,-z,max-page-size=16384`) for Android 15+ compliance.
- Explicit `chmod 755` executable permissions across all platform archive extractors.

## 0.0.2

- Fix Android JVM target compatibility between Java and Kotlin compilation tasks (`JavaVersion.VERSION_1_8` and `jvmTarget = '1.8'`).
- Enhanced example application with dynamic magnet title parsing and interactive per-file streaming selector.

## 0.0.1

- Initial production release of `torrserver_flutter`.
- Unified `TorrServerController` supporting Windows, Linux, macOS, Android, and iOS.
- Process-based subprocess controller with graceful signal shutdown for Windows, Linux, macOS, and Android.
- In-process static linking via `TorrServerKit.xcframework` and `dart:ffi` for iOS.
- Automated free port selection utility preventing `Port already in use` startup aborts.
- Typed REST API client matching TorrServer Swagger specifications.
- Kotlin ForegroundService for persistent background playback on Android 8.0+.
- Binary download and SHA-256 verification hooks for CMake, Gradle, and CocoaPods with offline override via `TORRSERVER_FLUTTER_LOCAL_BINARIES`.
- GPL-3.0 compliance disclosures (`NOTICE.md` and `LICENSE-GPL3`).
