Pod::Spec.new do |s|
  s.name             = 'torrserver_flutter'
  s.version          = '1.0.0'
  s.summary          = 'TorrServer Flutter macOS plugin'
  s.description      = <<-DESC
Flutter package wrapping TorrServer for macOS desktop via subprocess model.
                       DESC
  s.homepage         = 'https://github.com/torrserver-flutter/torrserver_flutter'
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
    VERSION="1.0.0"
    LOCAL_BIN="${TORRSERVER_FLUTTER_LOCAL_BINARIES}"
    mkdir -p bin

    if [ -n "$LOCAL_BIN" ] && [ -f "$LOCAL_BIN/torrserver-darwin-arm64" ]; then
      echo "Using local macOS binary from $LOCAL_BIN"
      cp "$LOCAL_BIN/torrserver-darwin-arm64" bin/torrserver
      chmod +x bin/torrserver
    elif [ ! -f "bin/torrserver" ]; then
      echo "Downloading TorrServer macOS binary from GitHub Releases..."
      curl -sL "https://github.com/torrserver-flutter/torrserver_flutter/releases/download/v${VERSION}/torrserver-darwin-arm64" -o bin/torrserver || true
      chmod +x bin/torrserver || true
    fi
  CMD
end
