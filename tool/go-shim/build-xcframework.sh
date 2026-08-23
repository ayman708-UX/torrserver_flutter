#!/bin/bash
set -e

# Build script for TorrServerKit.xcframework for iOS using gomobile
OUTPUT_DIR="${OUTPUT_DIR:-../../dist}"
mkdir -p "${OUTPUT_DIR}"

echo "=== Ensuring gomobile is installed ==="
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
gomobile init

echo "=== Fetching / preparing TorrServer source ==="
if [ ! -d "torrserver-src" ]; then
  git clone --depth 1 https://github.com/YouROK/TorrServer.git torrserver-src
  cd torrserver-src
  export NODE_OPTIONS=--openssl-legacy-provider
  go run gen_web.go
  cd ..
fi

echo "=== Building TorrServerKit.xcframework ==="
gomobile bind \
  -target=ios/arm64,iossimulator/arm64,iossimulator/amd64 \
  -iosversion=14.0 \
  -tags=nosqlite \
  -ldflags="-s -w -checklinkname=0" \
  -trimpath \
  -o "${OUTPUT_DIR}/TorrServerKit.xcframework" \
  .

echo "=== Zipping XCFramework for Release ==="
cd "${OUTPUT_DIR}"
zip -r -9 TorrServerKit.xcframework.zip TorrServerKit.xcframework
echo "Done! Built ${OUTPUT_DIR}/TorrServerKit.xcframework.zip"
