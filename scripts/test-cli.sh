#!/usr/bin/env bash
# Builds and runs the Swift Testing unit tests (FilmLabTests) on macOS without Xcode.
source "$(dirname "$0")/_toolchain.sh"
F="$CLT/Library/Developer/Frameworks"
IFS=$'\n'; SOURCES=($(app_sources)); TESTS=($(find "$ROOT/FilmLabTests" -name '*.swift' | sort)); unset IFS
cat > "$BUILD/TestMain.swift" <<'SWIFT'
import Testing
import Foundation
@main struct FilmLabCLITestRunner {
    static func main() async {
        let code: CInt = await Testing.__swiftPMEntryPoint(passing: nil)
        exit(code)
    }
}
SWIFT
swiftc -parse-as-library "${SWIFTC_FLAGS[@]}" -F "$F" -Xlinker -rpath -Xlinker "$F" -framework Testing \
  -plugin-path "$CLT/usr/lib/swift/host/plugins/testing" \
  "${SOURCES[@]}" "${TESTS[@]}" "$BUILD/TestMain.swift" -o "$BUILD/filmlab-tests"
cd "$ROOT" && "$BUILD/filmlab-tests" "$@"
