#!/usr/bin/env bash
# Build CleanMac in Release configuration and package it as a ZIP.
# Produces: dist/CleanMac-<version>.zip
#
# This script intentionally does NOT embed Developer ID credentials or run
# notarization. The output is ad-hoc signed and will trigger a Gatekeeper
# warning when opened on another Mac — see RELEASING.md.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

command -v xcodegen >/dev/null || {
  echo "error: xcodegen not found. Install it: brew install xcodegen" >&2
  exit 1
}
command -v xcodebuild >/dev/null || {
  echo "error: xcodebuild not found. Install Xcode." >&2
  exit 1
}

VERSION="$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
if [[ -z "${VERSION:-}" ]]; then
  echo "error: could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
ARCHIVE_PATH="$BUILD_DIR/CleanMac.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
ZIP_PATH="$DIST_DIR/CleanMac-$VERSION.zip"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Cleaning build artifacts"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "==> Archiving Release build (ad-hoc signed)"
xcodebuild \
  -project CleanMac.xcodeproj \
  -scheme CleanMac \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  archive

echo "==> Copying .app from archive"
mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVE_PATH/Products/Applications/CleanMac.app" "$EXPORT_DIR/"

echo "==> Zipping"
rm -f "$ZIP_PATH"
# -y preserves symlinks (important for .app bundle internals)
(cd "$EXPORT_DIR" && zip -qry "$ZIP_PATH" "CleanMac.app")

echo
echo "Done:"
echo "  version: $VERSION"
echo "  zip:     $ZIP_PATH"
echo "  size:    $(du -h "$ZIP_PATH" | awk '{print $1}')"
echo
echo "This build is ad-hoc signed. Gatekeeper will warn on first launch on"
echo "another Mac. See RELEASING.md for signing/notarization options."
