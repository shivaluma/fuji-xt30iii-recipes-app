#!/usr/bin/env bash
# Generates the synthetic benchmark screenshots into web/bench/fixtures (macOS, Command Line Tools).
source "$(dirname "$0")/../_toolchain.sh"
swiftc "${SWIFTC_FLAGS[@]}" "$ROOT/scripts/bench/generate-fixtures.swift" -o "$BUILD/generate-fixtures"
"$BUILD/generate-fixtures" "$ROOT/web/bench/fixtures"
