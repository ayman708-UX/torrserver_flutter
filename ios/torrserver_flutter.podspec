Pod::Spec.new do |s|
  s.name             = 'torrserver_flutter'
  s.version          = '0.0.7'
  s.summary          = 'TorrServer Flutter iOS plugin'
  s.description      = <<-DESC
A Flutter package embedding TorrServer as an in-process XCFramework for iOS.
                       DESC
  s.homepage         = 'https://github.com/ayman708-UX/torrserver_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'TorrServer Flutter Contributors' => 'contributors@torrserver.local' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  s.platform = :ios, '14.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '$(inherited) -framework SystemConfiguration'
  }
  s.swift_version = '5.0'

  s.frameworks = 'SystemConfiguration', 'Foundation', 'Security'
  s.vendored_frameworks = 'TorrServerKit.xcframework'

  # Download XCFramework hook
  s.prepare_command = <<-CMD
    set -e
    VERSION="0.0.7"
    LOCAL_BIN="${TORRSERVER_FLUTTER_LOCAL_BINARIES}"

    if [ -n "$LOCAL_BIN" ] && [ -d "$LOCAL_BIN/TorrServerKit.xcframework" ]; then
      echo "Using local TorrServerKit.xcframework from $LOCAL_BIN"
      rm -rf TorrServerKit.xcframework
      cp -R "$LOCAL_BIN/TorrServerKit.xcframework" .
    elif [ -n "$LOCAL_BIN" ] && [ -f "$LOCAL_BIN/TorrServerKit.xcframework.zip" ]; then
      echo "Unzipping local TorrServerKit.xcframework.zip from $LOCAL_BIN"
      rm -rf TorrServerKit.xcframework
      unzip -q "$LOCAL_BIN/TorrServerKit.xcframework.zip" -d .
    elif [ ! -d "TorrServerKit.xcframework" ]; then
      echo "Downloading TorrServerKit.xcframework from GitHub Releases..."
      curl -sL "https://github.com/ayman708-UX/torrserver_flutter/releases/download/v${VERSION}/checksums.txt" -o checksums.txt || true
      curl -sL "https://github.com/ayman708-UX/torrserver_flutter/releases/download/v${VERSION}/TorrServerKit.xcframework.zip" -o TorrServerKit.xcframework.zip || true
      if [ -f "TorrServerKit.xcframework.zip" ]; then
        if [ -f "checksums.txt" ]; then
          EXPECTED_HASH=$(grep "TorrServerKit.xcframework.zip" checksums.txt | awk '{print $1}')
          if [ -n "$EXPECTED_HASH" ]; then
            COMPUTED_HASH=$(shasum -a 256 TorrServerKit.xcframework.zip | awk '{print $1}')
            if [ "$EXPECTED_HASH" != "$COMPUTED_HASH" ]; then
              echo "Error: SHA-256 mismatch for TorrServerKit.xcframework.zip (expected $EXPECTED_HASH, got $COMPUTED_HASH)"
              rm -f TorrServerKit.xcframework.zip checksums.txt
              exit 1
            fi
            echo "Verified SHA-256 for TorrServerKit.xcframework.zip: $COMPUTED_HASH"
          fi
          rm -f checksums.txt
        fi

        unzip -q TorrServerKit.xcframework.zip -d . || true
        rm -f TorrServerKit.xcframework.zip
      fi
    fi
  CMD
end
