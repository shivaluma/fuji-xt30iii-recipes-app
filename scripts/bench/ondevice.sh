#!/usr/bin/env bash
# Runs the on-device (Vision + parser) baseline on the fixtures; score with `pnpm bench:ondevice` in web/.
source "$(dirname "$0")/../_toolchain.sh"
IFS=$'\n'; SRC=($(app_sources)); unset IFS
swiftc -parse-as-library "${SWIFTC_FLAGS[@]}" "${SRC[@]}" "$ROOT/scripts/bench/ondevice.swift" -o "$BUILD/ondevice-bench"
"$BUILD/ondevice-bench" "$ROOT/web/bench/results/ondevice.json" "$ROOT/web/bench/fixtures" "$@"
