Pod::Spec.new do |s|
  s.name             = 'torrserver_flutter'
  s.version          = '0.0.2'
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
    VERSION="0.0.2"
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
      curl -sL "https://github.com/ayman708-UX/torrserver_flutter/releases/download/v${VERSION}/TorrServerKit.xcframework.zip" -o TorrServerKit.xcframework.zip || true
      if [ -f "TorrServerKit.xcframework.zip" ]; then
        unzip -q TorrServerKit.xcframework.zip -d . || true
        rm -f TorrServerKit.xcframework.zip
      fi
    fi
  CMD
end
