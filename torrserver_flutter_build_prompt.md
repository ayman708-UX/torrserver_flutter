# BUILD SPEC: `torrserver_flutter` — Flutter package wrapping TorrServer

You are building a production-grade Flutter/Dart package called **`torrserver_flutter`** that embeds/controls **TorrServer** (`github.com/YouROK/TorrServer`, Go, GPL-3.0) so Flutter apps can stream torrents via TorrServer's HTTP API, on **Windows, Linux, macOS, Android, and iOS** (no web — TorrServer cannot run in a browser).

This document is your complete spec. Do not invent architecture that contradicts the facts stated below — they are verified from TorrServer's actual source repository, its `build-all.sh` build script, its DeepWiki documentation, and the Go mobile toolchain docs. Anything marked **[FACT]** is confirmed and must be treated as ground truth. Anything marked **[DECISION]** is a design choice you must implement exactly as specified. Anything marked **[YOUR JOB]** is something you must build because it does not exist upstream.

---

## 0. Reference architecture: `libtorrent_flutter` precedent

There is a sibling package, `libtorrent_flutter` (publisher `playtorrio.xyz`), already shipping for Windows/Linux/macOS/iOS/Android with an equivalent goal (embedding a native torrent engine in Flutter). Mirror its proven patterns wherever TorrServer's shape allows:

- **[FACT]** It ships an **XCFramework** (device `arm64-iphoneos` + simulator `arm64+x86_64-iphonesimulator` slices) rather than a fat `.a`, built via `xcodebuild -create-xcframework`.
- **[FACT]** Its podspec uses `vendored_frameworks` with SDK-conditional `-force_load` linker flags, and required adding a `SystemConfiguration.framework` dependency to fix an `Undefined symbol: _SCNetworkReachabilityCreateWithAddress` linker error on iOS release builds — **watch for this exact linker error and apply the same fix if it recurs.**
- **[FACT]** Prebuilt native binaries are **not bundled in the pub.dev tarball** (pub.dev has a 100 MB limit). They're **downloaded from a GitHub Release on first build**, wired into Gradle (Android), CMake (desktop), and CocoaPods (iOS) build hooks, cached so the download happens once per package version, with a documented offline/air-gapped override.
- **[FACT]** A prior bug in that package: concurrent HTTP range requests (from video-player seeking) overwrote a global mutable request-ID, aborting concurrent connections. **This exact bug class is directly relevant here** — TorrServer's HTTP layer will receive the same overlapping-range-request pattern from a video player doing seeks, so any bridging/proxy layer you add must not introduce global mutable per-request state.

**[DECISION]** `torrserver_flutter` follows this same "binaries hosted on GitHub Releases, fetched by platform build hooks, not bundled in the package tarball" model for every platform, including the iOS XCFramework.

---

## 1. What TorrServer is and how it's currently built — facts you must not contradict

### 1.1 Identity & license

- **[FACT]** Upstream: `github.com/YouROK/TorrServer`. License: **GPL-3.0** (confirmed in repo `LICENSE` and on `pkg.go.dev`).
- **[FACT]** It is an HTTP server: BitTorrent client (`anacrolix/torrent`) + caching/storage layer (`torrstor`) + HTTP streaming/DLNA/WebDAV/FUSE + React web UI + REST API. It downloads pieces on-demand, deadline/priority-aware around the active reader position (a real streaming engine, not naive sequential download).
- **[FACT]** Releases are versioned `MatriX.<n>` (e.g. `MatriX.143`). Built with **Go 1.26.x** as of the most recent releases (README states a floor of Go 1.20+, but CI is pinned newer — verify the exact pinned version in the target release's workflow file before building).

### 1.2 GPL-3.0 compliance — hard constraint, not optional

- **[DECISION — must implement]** Two different linking models exist in this package, with two different compliance postures:
  - **Subprocess model (Windows/Linux/macOS/Android):** TorrServer runs as a separate OS process, controlled over `localhost` HTTP. This is "mere aggregation" under GPL practice (FSF's own FAQ position) — it does **not** obligate the calling Flutter/Dart app's own source.
  - **In-process embedding (iOS only, and optionally a sandboxed macOS build):** the Go shim is statically linked into the app binary. This **is** a derivative work under GPLv3 §5/§6. When you build the iOS target, you must:
    1. Keep the **Go shim source** (see §4) in a public repo under GPLv3-compatible terms.
    2. Ship a `LICENSE-GPL3` file and an in-app "Open Source Licenses" screen crediting TorrServer/GPLv3, in any app that embeds the iOS build.
    3. Add a `NOTICE.md` to the package root explicitly stating: *"The iOS target statically links TorrServer (GPL-3.0). Apps embedding torrserver_flutter's iOS build inherit GPLv3 source-availability obligations for the combined work. This is not legal advice — consult counsel before App Store submission."*
  - Do not skip this. It is a real legal surface, not boilerplate.

### 1.3 Confirmed CLI flags you must expose from Dart

Expose these as typed parameters on the Dart `start()` API (do not hardcode them):

| Flag | Purpose | Default |
|---|---|---|
| `--port` / `-p` | HTTP web port | 8090 |
| `--ip` / `-i` | Bind address (repeatable, multi-interface) | — |
| `--sslport` | HTTPS port | 8091 |
| `--sslcert`, `--sslkey` | TLS cert/key paths | — |
| `-d` | DB/config directory | — |
| `--rdb` | Read-only DB mode (no persistence writes) | off |

- **[FACT — critical, drives your port-selection design]** TorrServer does **not** auto-retry on a bound port. If the configured port is already in use it **exits** with `"Port already in use! Please set different port."` **Your Dart wrapper is responsible for pre-selecting a genuinely free port** (bind a throwaway socket, read the OS-assigned port, close it, hand that number to TorrServer, accept the small TOCTOU race window) before ever launching/starting TorrServer. Do not assume TorrServer will find its own port.

### 1.4 Config system facts relevant to your Dart settings API

- **[FACT]** Two config layers exist: `ExecArgs` (CLI-derived, never persisted) and `BTSets` (persistent JSON, DB key `Settings/BitTorr`, live-editable via the web API's `SetBTSets`).
- **[FACT]** Storage backend selectable per category: `StoreSettingsInJson` (settings.json vs config.db/BoltDB) and `StoreViewedInJson` (viewed.json vs config.db). Default is JSON for both.
- **[FACT]** Documented defaults you should mirror as your Dart-side default `TorrServerSettings` object:

  | Field | Default |
  |---|---|
  | `CacheSize` | 64 MB |
  | `PreloadCache` | 50% |
  | `ConnectionsLimit` | 25 |
  | `RetrackersMode` | 1 |
  | `TorrentDisconnectTimeout` | 30s |
  | `ReaderReadAHead` | 95% |
  | `ResponsiveMode` | true |
  | `ShowFSActiveTorr` | true |
  | `StoreSettingsInJson` | true |
  | `EnableLPD` | true |
  | `LPDIPv6` | false |

- **[FACT]** Server-side validation clamps: `ReaderReadAHead` → [5,100], `PreloadCache` → [0,100]; zero `CacheSize`/`ConnectionsLimit`/`TorrentDisconnectTimeout` reset to their defaults; empty `TorrentsSavePath` force-disables `UseDisk`. **Do not re-implement this validation client-side as the source of truth** — it's enforced server-side; your Dart layer should just pass values through and surface server validation errors.
- **[FACT]** API docs are served at runtime at `/swagger/index.html` — use this (fetch the swagger JSON from a running instance) to generate/verify your Dart REST client models rather than hand-guessing the API shape.

---

## 2. Per-platform build facts (from `build-all.sh`, the actual upstream build script)

### 2.1 Desktop: Windows, Linux, macOS — already fully supported upstream

- **[FACT]** `build-all.sh`'s `PLATFORMS` array already includes `windows/amd64`, `windows/386`, `darwin/amd64`, `darwin/arm64`, `linux/amd64`, `linux/arm64`, `linux/arm7`, `linux/arm5`, `linux/386`, plus BSD/MIPS/RISC-V variants you can ignore.
- **[FACT]** Build command for every one of these:
  ```bash
  GOOS=${GOOS} GOARCH=${GOARCH} go build \
    -ldflags='-s -w -checklinkname=0' \
    -tags=nosqlite \
    -trimpath \
    -o ${BIN_FILENAME} ./cmd
  ```
  No CGO, no special toolchain, plain cross-compile. `-tags=nosqlite` means persistence is BoltDB (pure Go) + JSON, never CGO-SQLite — matches §1.4's config facts.
- **[DECISION]** You do **not** need to fork/modify TorrServer to get desktop binaries. Your GitHub Actions workflow clones the exact upstream tag/commit you're targeting and runs this build command as-is for `windows/amd64`, `linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64`. Skip the rest of the matrix (386/BSD/MIPS/RISC-V) unless explicitly asked later.
- **[DECISION — Dart-side architecture]** Desktop package logic is a pure **subprocess + HTTP client** package:
  1. Locate the bundled/downloaded platform binary (see §3 for the download-on-first-build mechanism).
  2. Pick a free port as described in §1.3.
  3. `Process.start(binaryPath, ['-p', port.toString(), '-d', appDataDir, ...userArgs])`.
  4. Poll `http://127.0.0.1:<port>/` until it responds (bounded retry loop, fail with a clear Dart exception after e.g. 10s).
  5. Expose `stop()` that sends the process a graceful termination signal (`Process.kill(ProcessSignal.sigint)` on Linux/macOS — matches TorrServer's documented `systemd` unit using SIGINT for stop; on Windows use `Process.kill()` since Windows has no POSIX signals) and awaits process exit with a timeout before force-killing.

### 2.2 Android — already fully supported upstream, NDK-dependent

- **[FACT]** `build-all.sh`'s Android section cross-compiles for `arm7`, `arm64`, `386`, `amd64` using the **Android NDK's own clang binaries directly** (not `gomobile`), with `CGO_ENABLED=1`:
  ```bash
  declare -a COMPILERS=(
    "arm7:armv7a-linux-androideabi21-clang"
    "arm64:aarch64-linux-android21-clang"
    "386:i686-linux-android21-clang"
    "amd64:x86_64-linux-android21-clang"
  )
  export NDK_VERSION="25.2.9519653"
  CC=$NDK_TOOLCHAIN/bin/$COMPILER CXX=$NDK_TOOLCHAIN/bin/$COMPILER++ \
  GOOS=android GOARCH=$GOARCH CGO_ENABLED=1 go build \
    -ldflags='-s -w -checklinkname=0' -tags=nosqlite -trimpath -o $BIN_FILENAME ./cmd
  ```
- **[FACT]** Minimum Android API level: **21** (from the `androideabi21`/`android21` NDK clang suffix).
- **[DECISION]** Reproduce this exact command in your GitHub Actions workflow using **NDK version `25.2.9519653`** (pin this exact version — do not let the Action install "latest NDK", it must match what upstream tests against). Build `arm64` and `amd64` at minimum (arm64 for real devices, amd64 for emulator testing); add `arm7`/`386` if you want full parity.
- **[DECISION — Dart-side architecture]** Same subprocess + HTTP client model as desktop (§2.1), because Android does **not** forbid subprocess execution the way iOS does. Differences from desktop:
  - Package the binary as a raw asset bundled per-ABI (`jniLibs`-style layout, or a Gradle download-on-build task — see §3), selected at runtime via `Platform.version`/ABI detection or a Flutter platform channel that reads `android.os.Build.SUPPORTED_ABIS`.
  - Android will kill background processes aggressively. You must implement (or clearly document as required) a **foreground Android Service** that keeps the TorrServer subprocess alive while the app is backgrounded and playback is active — this is an Android-platform concern, not something upstream TorrServer facts cover, so design it explicitly: a small Kotlin `ForegroundService` started when `start()` is called, stopped when `stop()` is called, showing a persistent "Streaming active" notification (required by Android 8+ foreground service rules).
  - Executable permission: after extracting/downloading the binary into app-private storage, `chmod` it executable (`Process.run('chmod', ['755', binaryPath])`) before `Process.start`.

### 2.3 iOS — **[YOUR JOB]** — nothing exists upstream, must be built from scratch

- **[FACT — critical]** There is **no `ios/*` entry anywhere** in `build-all.sh`'s `PLATFORMS` array, on any architecture. iOS support does not exist upstream at all.
- **[FACT]** iOS forbids arbitrary subprocess execution from within an app sandbox. The subprocess model from §2.1/§2.2 is **not viable** on iOS. TorrServer must run **in-process**, embedded as a linked library inside the Flutter app's iOS binary.
- **[FACT]** `server/cmd/main.go` is a plain `func main()` — TorrServer is **not currently structured as an importable library with an exported `Start()`/`Stop()` API**. Every upstream build path produces a standalone executable via `go build ... ./cmd`, never `-buildmode=c-archive` or a `gomobile bind`-compatible shape.
- **[FACT]** `server.WaitServer()` (in `server/server.go`) **blocks** the calling goroutine until shutdown — this is how the CLI binary stays alive. It cannot be called directly from a `gomobile bind`-exported function without spawning it on its own goroutine.
- **[FACT]** The documented shutdown path (`systemd` unit) is OS **signal-based**: `SIGINT` to stop, `SIGHUP` to reload. iOS has no equivalent signal-based process model for an in-process embedded library. **No confirmed public non-signal `Stop()` API exists in TorrServer's Go packages** based on available research — this must be treated as an **open risk**, not a solved problem, until you've actually read the full body of `server/server.go`.
- **[FACT — favorable]** `server/server.go`, `server/settings/settings.go`, `server/web/server.go` etc. are already **separate, importable Go packages** under `server/`, not folded into `cmd/main.go`. This makes wrapping them viable without modifying TorrServer's own internals, for everything except possibly the shutdown gap above.

#### 2.3.1 Required new Go shim package — build this exactly

**[YOUR JOB]** Create a new, small Go package (e.g. `torrserver-mobile-shim`, your own repo, GPLv3-licensed per §1.2) that:

1. Imports TorrServer's `server` and `settings` Go packages as a library dependency (via Go modules, pinned to a specific upstream commit/tag).
2. Replicates `main.go`'s + `server.Start()`'s initialization sequence **programmatically** (not via CLI-arg parsing): call `settings.InitSets()` with an explicit config directory, then the equivalent of `server.Start()` with an explicit port/bind-address, instead of relying on `alexflint/go-arg` CLI parsing.
3. Runs the blocking `server.WaitServer()`-equivalent call **inside its own goroutine**, so your exported start function returns control to the caller immediately.
4. Exports **C-ABI functions** via cgo `//export` comments, compatible with `gomobile bind`'s XCFramework output mode:
   ```go
   //export StartServer
   func StartServer(port C.int, dataDir *C.char) *C.char // returns error string or NULL

   //export StopServer
   func StopServer() *C.char // returns error string or NULL

   //export IsRunning
   func IsRunning() C.int // 1 or 0
   ```
5. **Solve the shutdown gap explicitly.** Before writing this shim, read the full body of `server/server.go` in the pinned upstream commit and determine:
   - If an exported cancellation mechanism (context, channel, or exported function) already exists → wire `StopServer()` to it directly.
   - If it does not exist → you have two options, in order of preference: (a) submit/maintain a small upstream-compatible patch adding a real `Stop(ctx)` function to TorrServer's `server` package (best long-term, but means you're tracking a fork or an open PR), or (b) as a fallback, send the equivalent of `SIGINT` to *your own process* from within the shim (`syscall.Kill(os.Getpid(), syscall.SIGINT)` works in-process on Darwin/iOS since it's the same process's signal handler, not cross-process) if TorrServer's internals register a signal handler for this — verify this actually triggers clean shutdown before shipping it as the solution; do not assume it works without testing.
   - Document whichever path you took in the shim's README, explicitly, since this is the single riskiest unresolved piece of the whole port.

#### 2.3.2 Building the XCFramework

- **[FACT]** `gomobile bind -target=ios/arm64,iossimulator/arm64` (and the umbrella `-target=darwin` for ios+iossimulator+macos+maccatalyst) directly produces an **XCFramework** as a first-class output — you do **not** need to hand-stitch `.a` files with `xcodebuild -create-xcframework` the way `libtorrent_flutter`'s C++ side does; `gomobile bind` does this internally for Go.
- **[FACT]** Default `-iosversion` is **13.0** if unspecified — pass this explicitly rather than relying on the default, so it's visible in your build script: `gomobile bind -target=ios/arm64,iossimulator/arm64 -iosversion=13.0 -o TorrServerKit.xcframework ./shim`.
- **[FACT — toolchain risk, must smoke-test before committing]** A real precedent project (`outline-go-tun2socks`, Google/Jigsaw's Outline VPN client — same pattern: Go networking server compiled via `gomobile bind` into iOS/macOS/Android frameworks) documented that as of Go 1.13, `gomobile` did **not** support building macOS frameworks and they had to **patch gomobile itself** to get macOS output. The officially-added `macos`/`maccatalyst` targets (from the later `GOOS=ios` support PR) may or may not have fully closed this gap. **Do not assume macOS-via-gomobile works — the very first CI job you write (§5) must smoke-test a bare `gomobile bind -target=ios/arm64,iossimulator/arm64 ./shim` against the actual shim module and confirm it produces a working XCFramework before any further iOS work proceeds.** If macOS-via-gomobile is needed later, treat it as a separate, unverified stretch goal, not part of the core deliverable (macOS is already solved via §2.1's subprocess model — you do not need gomobile for macOS at all).
- **[FACT]** Multiple long-standing `golang/go` issues (#32963, #36665, #16806, #12028) document iOS/gomobile build friction: mandatory Xcode code-signing identity for real builds (no default signing identity ⇒ hard failure, not warning — irrelevant for simulator-only CI, relevant for any real-device job), `ENABLE_BITCODE`/linker flag conflicts on older Xcode/Go combos, and historical Go-modules resolution gaps in `gomobile bind` specifically for iOS (Android was unaffected). **[DECISION]** Pin exact Go, Xcode, and `gomobile` versions together in the CI workflow (see §5) and re-verify on every version bump — do not use "latest" for any of these three in CI.
- **[FACT — unresolved, first thing to test]** Whether `anacrolix/torrent` and TorrServer's full transitive dependency graph compiles cleanly under `GOOS=ios` is **untested/unverified** in all available research. This must be your literal first experiment: run `gomobile bind -target=ios/arm64 ./shim` against the real module before writing any further shim logic, since it will surface any real incompatibility immediately and cheaply. If it fails, diagnosing/patching the offending dependency is now the critical path — treat this as a checkpoint, not an assumption.

#### 2.3.3 Dart ↔ Go bridge on iOS

**[DECISION]** Use **Dart FFI** (`dart:ffi`), not a platform channel, to call into the XCFramework's exported C functions directly from Dart — this avoids an extra Swift/Obj-C shim layer and keeps the API surface identical in shape to how you'd call a native library on desktop. Concretely:
1. Add the XCFramework to the package's `ios/torrserver_flutter.podspec` via `vendored_frameworks`, mirroring `libtorrent_flutter`'s pattern (SDK-conditional `-force_load` if you hit the same undefined-symbol class of linker error; add `SystemConfiguration.framework` proactively since `libtorrent_flutter` needed it for an equivalent reason).
2. Write a thin `dart:ffi` binding (`lib/src/ios_ffi_bindings.dart`) declaring `StartServer`, `StopServer`, `IsRunning` with matching C signatures.
3. The **public Dart API must be identical** across all five platforms (see §6) — internally, the iOS implementation calls FFI functions; the desktop/Android implementation spawns a subprocess and talks HTTP. Both implementations must converge on the same `TorrServerController` interface so app code never branches on platform.
4. After `StartServer()` returns successfully via FFI, the running instance is still just a normal `127.0.0.1:<port>` HTTP server from the Dart app's point of view — so your REST client, torrent-add/list/remove calls, and stream-URL generation code (§6) work **identically** on iOS as everywhere else; only the process-lifecycle layer differs.

### 2.4 What NOT to build

- **[DECISION]** Do **not** implement the GStreamer (`-gst`) build variant. **[FACT]** It's `CGO_ENABLED=0`, dynamically loads GStreamer 1.22+ at runtime, is limited to "Windows amd64, Linux amd64/arm64, and macOS amd64/arm64" only (no Android, no iOS, no runtime toggle to add it to a standard binary — it's a compile-time-only build tag). It is irrelevant to a cross-platform mobile-inclusive package. Track the plain, non-`gst` build everywhere.

---

## 3. Native binary distribution mechanism

**[DECISION — mirror `libtorrent_flutter` exactly]**

1. GitHub Actions (§5) builds every platform binary/framework on tag push and uploads them as assets on a **GitHub Release** matching the package's semver (e.g. release `v1.0.0` gets `torrserver-windows-amd64.exe`, `torrserver-linux-amd64`, `torrserver-linux-arm64`, `torrserver-darwin-amd64`, `torrserver-darwin-arm64`, `torrserver-android-arm64`, `torrserver-android-amd64`, `TorrServerKit.xcframework.zip`).
2. Do **not** commit these binaries into the pub.dev package tarball (100 MB limit, and it bloats every consumer's `pub get`).
3. Each platform's build system fetches its own binary/framework on first build, and caches it:
   - **CMake** (`windows/CMakeLists.txt`, `linux/CMakeLists.txt`, `macos/`... via a shared CMake include or a pre-build script): download+verify checksum, extract to a build cache dir, skip if already present for this package version.
   - **Gradle** (`android/build.gradle`): a custom Gradle task, `downloadTorrServerBinaries`, wired as a dependency of `preBuild`, same download/checksum/cache logic.
   - **CocoaPods** (`ios/torrserver_flutter.podspec`): a `script_phase` or `prepare_command` that downloads and unzips the XCFramework before pod install completes.
4. **[DECISION]** Pin the exact GitHub Release URL by package version (embed the version string in the download URL, e.g. `https://github.com/<you>/torrserver_flutter/releases/download/v{{version}}/...`) so pub.dev package versions map 1:1 to binary versions — never fetch "latest".
5. Provide a documented offline/air-gapped override: an environment variable (e.g. `TORRSERVER_FLUTTER_LOCAL_BINARIES=/path/to/dir`) that all three build-system hooks check first before attempting any network download.
6. Verify every downloaded artifact's checksum against a `checksums.txt` also published on the Release, before use — fail the build loudly if it doesn't match (supply-chain integrity, not optional).

---

## 4. Package repository layout

```
torrserver_flutter/
  lib/
    torrserver_flutter.dart               # public export surface
    src/
      torrserver_controller.dart          # abstract interface, platform-agnostic
      torrserver_controller_subprocess.dart  # Windows/Linux/macOS/Android impl
      torrserver_controller_ios.dart      # iOS FFI impl
      ios_ffi_bindings.dart               # dart:ffi bindings to TorrServerKit
      rest_client.dart                    # typed HTTP client for TorrServer's REST/Swagger API
      models/                             # Torrent, TorrServerSettings, etc. — generated/verified against /swagger/index.html
      port_finder.dart                    # free-port selection utility (see §1.3)
      binary_locator.dart                 # resolves path to the downloaded native binary/framework per-platform
  windows/                                # CMake plugin scaffold + binary-download hook
  linux/                                  # CMake plugin scaffold + binary-download hook
  macos/                                  # CocoaPods podspec + binary-download hook (subprocess model, NOT the XCFramework)
  android/                                # Gradle plugin scaffold + NDK-binary-download hook + ForegroundService (Kotlin)
  ios/
    torrserver_flutter.podspec            # vendored_frameworks -> TorrServerKit.xcframework
    Classes/                              # minimal Obj-C/Swift plugin registration only — no business logic here, that's in Dart FFI
  example/                                # a real runnable example app exercising every platform
  test/                                   # Dart unit tests (mock REST client, port finder, controller interface conformance)
  integration_test/                       # real end-to-end: start server, add a well-known legal test torrent (e.g. a Linux ISO or Big Buck Bunny's public magnet), verify it lists, verify /stream URL returns 200 + correct Content-Type, stop server, verify process/framework is actually down
  tool/
    go-shim/                              # the new Go shim package from §2.3.1, GPLv3-licensed, its own go.mod
  .github/workflows/
    build-desktop.yml
    build-android.yml
    build-ios.yml
    test-ios-simulator.yml
    test-dart.yml
    release.yml
  NOTICE.md                               # GPLv3 disclosure per §1.2
  LICENSE                                 # package's own license (your choice, e.g. MIT/BSD for the Dart glue)
  LICENSE-GPL3                            # full GPLv3 text, required because of embedded TorrServer
  CHANGELOG.md
  README.md
  pubspec.yaml
```

---

## 5. GitHub Actions — exact workflows required

All workflows live in `.github/workflows/`. Use a matrix wherever the same steps repeat across targets. Every build job must **fail the whole workflow** on any error — no `continue-on-error` on build steps (only acceptable on genuinely flaky infra steps like simulator boot, explicitly justified with a comment).

### 5.1 `test-dart.yml` — pure Dart/Flutter checks, every push/PR
- `flutter test` (unit tests: REST client mocking, port finder, controller interface conformance across both implementations using a fake FFI/fake process backend).
- `flutter analyze` with zero warnings allowed.
- `dart format --set-exit-if-changed .`

### 5.2 `build-desktop.yml` — Windows/Linux/macOS binaries
- Matrix: `{goos: windows, goarch: amd64, runs-on: windows-latest}`, `{goos: linux, goarch: amd64, runs-on: ubuntu-latest}`, `{goos: linux, goarch: arm64, runs-on: ubuntu-latest}` (cross-compiled, no native arm64 runner needed since it's a pure-Go cross build), `{goos: darwin, goarch: amd64, runs-on: macos-latest}`, `{goos: darwin, goarch: arm64, runs-on: macos-latest}`.
- Steps: checkout pinned upstream TorrServer commit/tag → `setup-go` pinned to the exact Go version TorrServer's own CI uses (verify this per §1.1, do not assume) → build web UI (`NODE_OPTIONS=--openssl-legacy-provider`, `go run gen_web.go`) → `swag init -g web/server.go` → run the exact `go build` command from §2.1 → upload artifact.
- On desktop, also run a **smoke test**: launch the just-built binary on a free port, curl `http://127.0.0.1:<port>/`, assert HTTP 200, then send SIGINT/kill and assert clean exit — catches a broken build before it ever reaches a release.

### 5.3 `build-android.yml` — NDK cross-compile
- `runs-on: ubuntu-latest`. Install/cache **NDK version `25.2.9519653`** explicitly (do not use whatever default the Android SDK action installs).
- Matrix: `arm64` (`aarch64-linux-android21-clang`), `amd64` (`x86_64-linux-android21-clang`) at minimum; add `arm7`/`386` if desired.
- Run the exact `CC=... CXX=... CGO_ENABLED=1 go build ...` command from §2.2.
- Smoke test: same launch/curl/kill pattern as §5.2, run under an Android emulator (`amd64` build) via `reactivecircus/android-emulator-runner` or similar, API level 21+ image.

### 5.4 `build-ios.yml` — the risky one, sequenced to fail fast and cheap
- `runs-on: macos-15` (or newer — check current available label at build time, do not hardcode a stale one).
- **Step order matters — do the cheapest, most likely-to-fail step first:**
  1. Checkout the Go shim (`tool/go-shim/`) and its pinned TorrServer dependency.
  2. Pin exact `Go`, `Xcode`, and `gomobile` versions (record them as explicit `env:` vars at the top of the workflow file, not inferred from the runner image).
  3. **First real step: `gomobile bind -target=ios/arm64,iossimulator/arm64 -iosversion=13.0 -o TorrServerKit.xcframework ./tool/go-shim` — if this fails, stop here and fix the dependency-graph/toolchain issue before writing anything else.** This directly tests the unresolved question from §2.3.2/§2.3.3.
  4. If it succeeds: upload the XCFramework as a build artifact.
  5. Build the Flutter `example/` app's iOS target against the just-built XCFramework using the iOS Simulator SDK: `xcodebuild build -workspace ... -scheme Runner -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGNING_ALLOWED=NO`. **`CODE_SIGNING_ALLOWED=NO` is required and correct here** — no Apple Developer account or signing identity is needed for simulator-only builds; this only matters for real-device installs or App Store submission, neither of which this CI job does.
  6. Boot the simulator and launch the app: `xcrun simctl boot "iPhone 16"` then `xcrun simctl launch booted <bundle-id>`, or drive it via an actual `XCUITest`/Flutter `integration_test` target for a real pass/fail signal rather than just eyeballing logs.
  7. Assert: app launches without a Go panic in the log, the embedded server responds on `127.0.0.1:<port>` within a bounded timeout (e.g. `xcrun simctl spawn booted curl http://127.0.0.1:<port>/` or equivalent from within the test), and `StopServer()` returns cleanly.
  8. **Known infra flakiness to handle explicitly:** GitHub's macOS/simulator images have documented issues (simulator fails to boot with `No matching device in set at XCTestDevices`, missing iOS runtime after Xcode version bumps). Add a retry-with-backoff **only** around the simulator-boot step (not around your app's own build/launch/assert steps), and label failures distinctly in the job summary so a red run is diagnosable as "infra flake" vs "real regression" at a glance.

### 5.5 `test-ios-simulator.yml`
- Can be folded into `build-ios.yml`'s later steps (§5.4.5–5.4.8), or kept separate and triggered `workflow_run` after a successful `build-ios.yml`. Either is fine — the key requirement is that **every PR touching `tool/go-shim/`, `ios/`, or the Dart FFI bindings must run this before merge**, since this is the one platform with zero prior art and the most ways to silently break.

### 5.6 `release.yml` — triggered on version tag push (`v*.*.*`)
- Depends on (`needs:`) all of `build-desktop.yml`, `build-android.yml`, `build-ios.yml` succeeding.
- Downloads all artifacts, generates `checksums.txt` (SHA-256 of every asset), creates a GitHub Release matching the tag, uploads all binaries/frameworks + `checksums.txt`.
- **Does not** auto-publish to pub.dev in the same job unless explicitly requested later — leave `pub publish` as a manual, separate step so a maintainer reviews the CHANGELOG first.

---

## 6. Public Dart API surface — must be identical across all 5 platforms

```dart
abstract class TorrServerController {
  /// Starts TorrServer (subprocess on desktop/Android, in-process FFI on iOS).
  /// Picks a free port automatically unless [port] is given.
  /// Throws [TorrServerStartException] on failure (binary missing, port
  /// unavailable after retry, process exited immediately, FFI start returned
  /// an error string, etc.) — never returns a "maybe started" ambiguous state.
  Future<void> start({int? port, TorrServerSettings? settings, Directory? dataDir});

  /// Stops TorrServer cleanly. Must actually wait for shutdown to complete
  /// (bounded timeout, then force-kill on subprocess platforms) before
  /// returning, not just "signal sent."
  Future<void> stop();

  /// True only if the server is actually confirmed running (last successful
  /// health check), not just "start() was called."
  bool get isRunning;

  /// Base URL of the running instance, e.g. http://127.0.0.1:8090 — null if not running.
  Uri? get baseUrl;

  // --- Torrent operations (thin typed wrappers over TorrServer's REST API,
  //     verified against the running instance's own /swagger/index.html —
  //     do not hand-guess field names) ---
  Future<TorrentInfo> addTorrent({String? magnet, Uint8List? torrentFile, String? title});
  Future<List<TorrentInfo>> listTorrents();
  Future<void> removeTorrent(String hash);
  Uri streamUrl(String hash, {int fileIndex = 0}); // constructs the /stream/{hash} URL for a video player
  Future<TorrServerSettings> getSettings();
  Future<void> setSettings(TorrServerSettings settings);
}

TorrServerController createTorrServerController(); // factory, picks subprocess or iOS-FFI impl based on Platform
```

- App code (including your `example/`) must never branch on `Platform.isIOS` etc. — that branching lives entirely inside the package, behind this one interface.
- `TorrServerSettings` fields and defaults must match §1.4's table exactly.
- Every method that can fail must throw a specific typed exception, not a generic `Exception`, so app developers can catch/handle each failure mode (binary-missing, port-unavailable, process-crashed, ffi-error, http-timeout, invalid-magnet, etc.) distinctly.

---

## 7. Testing requirements — definition of done

Do not consider this package complete until all of the following pass in CI:

1. `flutter analyze` clean, `dart format` clean (§5.1).
2. Unit tests cover: port finder logic, REST client against a mocked HTTP server, controller interface conformance for both the subprocess and (mocked-FFI) iOS implementations.
3. Desktop smoke test (§5.2) passes on real Windows, Linux (amd64+arm64 cross-built), and macOS (amd64+arm64) runners/binaries.
4. Android smoke test (§5.3) passes on a real emulator, API 21+.
5. iOS: `gomobile bind` succeeds producing a valid XCFramework (§5.4 step 3), the example app builds and launches on the iOS Simulator with `CODE_SIGNING_ALLOWED=NO`, and the in-process server responds to a health-check HTTP request from within the running app — with zero Go panics in the log.
6. `integration_test/` end-to-end flow (add a real, legal, well-known magnet/torrent — e.g. a public-domain Linux distro ISO or a Creative-Commons-licensed test video — list it, request its stream URL, confirm the HTTP response is a valid video stream with correct `Content-Type` and that byte-range requests work, i.e. a `Range: bytes=1000-` request returns `206 Partial Content` with the correct slice) passes on at least desktop and one mobile target.
7. `NOTICE.md` and `LICENSE-GPL3` are present and accurate (§1.2) before any tagged release.
8. `release.yml` produces a GitHub Release with all five platforms' artifacts plus a matching `checksums.txt`, and the version number in the release tag matches `pubspec.yaml`.

---

## 8. Explicitly unresolved risks — do not silently "solve" these, surface them

Call these out in the shim/package README exactly as flagged here, since they are open questions from the research this spec is based on, not settled facts:

1. Whether `anacrolix/torrent` and TorrServer's full dependency graph compiles cleanly under `GOOS=ios` — first thing tested by §5.4 step 3; if it fails, that failure and your resolution must be documented, not hidden.
2. Whether TorrServer's `server` package exposes (or needs a new/forked) real programmatic shutdown function distinct from OS-signal handling — resolve per §2.3.1 point 5, document which path was taken.
3. Whether the officially-added `gomobile bind -target=macos` fully supersedes `outline-go-tun2socks`'s need to patch `gomobile` for macOS framework output — irrelevant to this package's core deliverable (macOS uses the subprocess model, not gomobile) but flag it in the README as untested if anyone later wants an in-process macOS build (e.g. for App Store sandboxing).
4. Whether BoltDB's mmap-based storage engine has any sandboxed-filesystem quirks under iOS's app sandbox — not researched upstream; add this as a specific thing to watch for if the iOS integration test in §7.6 shows any data-persistence flakiness.
5. **App Store distribution policy, not a technical risk:** Apple has precedent rejecting BitTorrent/media-downloading apps under Guideline 5.2.3 (Legal — Intellectual Property), and even forced removal of a torrenting app from AltStore PAL under EU DMA rules. This package can be built, tested via simulator, and sideloaded/distributed outside the App Store without issue — but document plainly in the README that **public App Store distribution of an app embedding this package is likely to be rejected**, so downstream developers aren't surprised.
