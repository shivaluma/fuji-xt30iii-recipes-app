#!/usr/bin/env bash
# Type-checks all FilmLab sources (Domain, Services, SwiftUI features) against the macOS SDK.
# iOS-only branches (#if os(iOS)) are not covered; build in Xcode for full iOS verification.
source "$(dirname "$0")/_toolchain.sh"
mapfile_compat() { local IFS=$'\n'; SOURCES=($(app_sources)); }
mapfile_compat
swiftc -typecheck "${SWIFTC_FLAGS[@]}" "${SOURCES[@]}" "$@"
echo "typecheck OK (${#SOURCES[@]} files)"
