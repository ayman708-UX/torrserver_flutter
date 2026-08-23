#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERSION="0.0.3"
TARGET_DIR="$ROOT_DIR/ios/TorrServerKit.xcframework"

if [ -d "$ROOT_DIR/dist/TorrServerKit.xcframework" ]; then
  echo "Using built TorrServerKit.xcframework from dist/"
  rm -rf "$TARGET_DIR"
  cp -R "$ROOT_DIR/dist/TorrServerKit.xcframework" "$ROOT_DIR/ios/"
elif [ -n "$TORRSERVER_FLUTTER_LOCAL_BINARIES" ] && [ -d "$TORRSERVER_FLUTTER_LOCAL_BINARIES/TorrServerKit.xcframework" ]; then
  echo "Using local TorrServerKit.xcframework from $TORRSERVER_FLUTTER_LOCAL_BINARIES"
  rm -rf "$TARGET_DIR"
  cp -R "$TORRSERVER_FLUTTER_LOCAL_BINARIES/TorrServerKit.xcframework" "$ROOT_DIR/ios/"
elif [ ! -d "$TARGET_DIR" ]; then
  echo "Fetching TorrServerKit.xcframework from GitHub Releases (v${VERSION})..."
  TEMP_ZIP="$ROOT_DIR/ios/TorrServerKit.xcframework.zip"
  curl -sL "https://github.com/ayman708-UX/torrserver_flutter/releases/download/v${VERSION}/TorrServerKit.xcframework.zip" -o "$TEMP_ZIP" || true
  if [ -f "$TEMP_ZIP" ]; then
    unzip -q "$TEMP_ZIP" -d "$ROOT_DIR/ios/" || true
    rm -f "$TEMP_ZIP"
  fi
fi
