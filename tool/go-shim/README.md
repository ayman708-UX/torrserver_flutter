# torrserver-mobile-shim

Go mobile shim wrapping **TorrServer** (`github.com/YouROK/TorrServer`, GPL-3.0) for in-process embedding on **iOS** as an XCFramework (`TorrServerKit.xcframework`).

## Architecture & Shutdown Resolution

Upstream TorrServer was originally written primarily as a standalone CLI executable. This shim solves two critical challenges for iOS:
1. **Programmatic Lifecycle**: Instead of parsing CLI flags with `go-arg`, `StartServer(port, dataDir)` directly configures `settings.Path` and `settings.Args`, executes pre-flight port binding checks to prevent aborts, and starts `server.Start()` on a dedicated goroutine.
2. **Shutdown Gap Resolution**: Upstream `server/server.go` exports `server.Stop()`, which invokes `web.Stop()` (cleaning up active torrent client sessions, unmounting FUSE, stopping Bonjour/DLNA) and `settings.CloseDB()`. `StopServer()` invokes `server.Stop()` and awaits graceful teardown with a timeout.

## Exported C-ABI Functions

```c
// Starts TorrServer on the specified port and data directory.
// Returns NULL (nil) on success, or an allocated error C-string on failure.
char* StartServer(int port, char* dataDir);

// Stops the embedded TorrServer.
// Returns NULL on success, or an error string on failure.
char* StopServer(void);

// Returns 1 if running, 0 if stopped.
int IsRunning(void);
```

## GPL-3.0 Compliance

This Go shim statically links TorrServer and is released under the **GNU General Public License v3.0**. Applications embedding this iOS build inherit GPLv3 source-availability obligations for the combined work.
