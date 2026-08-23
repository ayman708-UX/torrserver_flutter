# Notice & GPL-3.0 Compliance

## iOS Target Compliance Notice
> **The iOS target statically links TorrServer (GPL-3.0). Apps embedding `torrserver_flutter`'s iOS build inherit GPLv3 source-availability obligations for the combined work. This is not legal advice — consult counsel before App Store submission.**

## Upstream Project
- **TorrServer**: [https://github.com/YouROK/TorrServer](https://github.com/YouROK/TorrServer)
- **Author**: YouROK and contributors
- **License**: GNU General Public License v3.0 (GPL-3.0)

## Linking & Licensing Model by Platform
1. **Desktop (Windows, Linux, macOS) & Android**:
   - TorrServer runs as an independent subprocess communicating strictly over `127.0.0.1` HTTP loopback sockets.
   - Under Free Software Foundation (FSF) GPL guidance, process-level communication across standard OS process boundaries is classified as "mere aggregation" and does not obligate the calling Flutter application source code.
2. **iOS**:
   - iOS app sandbox restrictions disallow arbitrary subprocess spawning. TorrServer is statically linked into the application binary as an XCFramework (`TorrServerKit.xcframework`) via Go mobile (`gomobile bind`) and Dart FFI (`dart:ffi`).
   - Consequently, the resulting iOS combined binary is considered a derivative work under GPLv3 §5/§6.
   - Any app embedding `torrserver_flutter` on iOS must provide source code availability under GPLv3 and display appropriate open-source license credits.

See [LICENSE-GPL3](LICENSE-GPL3) for the full text of the GNU General Public License v3.0.
