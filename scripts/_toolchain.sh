# Shared helpers for running the FilmLab sources through swiftc WITHOUT Xcode.
# Used to type-check and unit-test on a Mac with only the Command Line Tools installed.
# With Xcode installed, prefer: xcodegen && xcodebuild test (see README).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build-cli"
mkdir -p "$BUILD"
CLT=/Library/Developer/CommandLineTools
SWIFTC_FLAGS=(-target arm64-apple-macos14.0 -swift-version 5 -D FILMLAB_CLI)
# Some CLT installs ship a stale duplicate usr/include/swift/module.modulemap that makes every
# Foundation import fail ("redefinition of module 'SwiftBridging'"). Mask it with a VFS overlay
# instead of modifying system files.
if [[ -f "$CLT/usr/include/swift/module.modulemap" && -f "$CLT/usr/include/swift/bridging.modulemap" ]]; then
  : > "$BUILD/empty.modulemap"
  cat > "$BUILD/overlay.yaml" <<YAML
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "directory", "name": "$CLT/usr/include/swift", "contents": [ { "type": "file", "name": "module.modulemap", "external-contents": "$BUILD/empty.modulemap" } ] } ] }
YAML
  SWIFTC_FLAGS+=(-vfsoverlay "$BUILD/overlay.yaml")
fi
# Sources compiled on macOS: everything except the iOS app entry point.
app_sources() { find "$ROOT/FilmLab" -name '*.swift' ! -path '*/App/FilmLabApp.swift' | sort; }
