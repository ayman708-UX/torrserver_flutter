Pod::Spec.new do |s|
  s.name             = 'torrserver_flutter'
  s.version          = '0.0.2'
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
    VERSION="0.0.2"
    LOCAL_BIN="${TORRSERVER_FLUTTER_LOCAL_BINARIES}"
    mkdir -p bin

    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
      BIN_NAME="torrserver-darwin-amd64"
    else
      BIN_NAME="torrserver-darwin-arm64"
    fi

    if [ -n "$LOCAL_BIN" ] && [ -f "$LOCAL_BIN/$BIN_NAME" ]; then
      echo "Using local macOS binary from $LOCAL_BIN"
      cp "$LOCAL_BIN/$BIN_NAME" bin/torrserver
      chmod +x bin/torrserver
    elif [ ! -f "bin/torrserver" ]; then
      echo "Downloading TorrServer macOS binary ($BIN_NAME) from GitHub Releases..."
      curl -sL "https://github.com/ayman708-UX/torrserver_flutter/releases/download/v${VERSION}/${BIN_NAME}" -o bin/torrserver || true
      chmod +x bin/torrserver || true
    fi
  CMD
end
