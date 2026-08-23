Pod::Spec.new do |s|
  s.name             = 'torrserver_flutter'
  s.version          = '0.0.3'
  s.summary          = 'TorrServer Flutter macOS plugin'
  s.description      = <<-DESC
Flutter package wrapping TorrServer for macOS desktop via subprocess model.
                       DESC
  s.homepage         = 'https://github.com/ayman708-UX/torrserver_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'TorrServer Flutter Contributors' => 'contributors@torrserver.local' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  # Download macOS TorrServer binary hook
  s.prepare_command = <<-CMD
    set -e
    VERSION="0.0.3"
    LOCAL_BIN="${TORRSERVER_FLUTTER_LOCAL_BINARIES}"
    mkdir -p bin

    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
      ARCH_NAME="amd64"
    else
      ARCH_NAME="arm64"
    fi

    ARCHIVE_NAME="torrserver-darwin-${ARCH_NAME}.tar.gz"
    BIN_NAME="torrserver-darwin-${ARCH_NAME}"

    if [ -n "$LOCAL_BIN" ] && [ -f "$LOCAL_BIN/$ARCHIVE_NAME" ]; then
      echo "Extracting local macOS archive from $LOCAL_BIN/$ARCHIVE_NAME"
      tar -xzf "$LOCAL_BIN/$ARCHIVE_NAME" -C bin/
      if [ -f "bin/$BIN_NAME" ]; then
        mv "bin/$BIN_NAME" bin/torrserver
      fi
      chmod 755 bin/torrserver
    elif [ -n "$LOCAL_BIN" ] && [ -f "$LOCAL_BIN/$BIN_NAME" ]; then
      echo "Using local macOS binary from $LOCAL_BIN"
      cp "$LOCAL_BIN/$BIN_NAME" bin/torrserver
      chmod 755 bin/torrserver
    elif [ ! -f "bin/torrserver" ]; then
      echo "Downloading TorrServer macOS compressed archive ($ARCHIVE_NAME) from GitHub Releases..."
      curl -sL "https://github.com/ayman708-UX/torrserver_flutter/releases/download/v${VERSION}/checksums.txt" -o "bin/checksums.txt" || true
      curl -sL "https://github.com/ayman708-UX/torrserver_flutter/releases/download/v${VERSION}/${ARCHIVE_NAME}" -o "bin/${ARCHIVE_NAME}" || true
      if [ -f "bin/${ARCHIVE_NAME}" ]; then
        if [ -f "bin/checksums.txt" ]; then
          EXPECTED_HASH=$(grep "$ARCHIVE_NAME" bin/checksums.txt | awk '{print $1}')
          if [ -n "$EXPECTED_HASH" ]; then
            COMPUTED_HASH=$(shasum -a 256 "bin/${ARCHIVE_NAME}" | awk '{print $1}')
            if [ "$EXPECTED_HASH" != "$COMPUTED_HASH" ]; then
              echo "Error: SHA-256 checksum mismatch for $ARCHIVE_NAME (expected $EXPECTED_HASH, got $COMPUTED_HASH)"
              rm -f "bin/${ARCHIVE_NAME}" bin/checksums.txt
              exit 1
            fi
            echo "Verified SHA-256 for $ARCHIVE_NAME: $COMPUTED_HASH"
          fi
          rm -f bin/checksums.txt
        fi

        tar -xzf "bin/${ARCHIVE_NAME}" -C bin/ || true
        if [ -f "bin/$BIN_NAME" ]; then
          mv "bin/$BIN_NAME" bin/torrserver || true
        fi
        rm -f "bin/${ARCHIVE_NAME}"
        chmod 755 bin/torrserver || true
      fi
    fi
  CMD
end
