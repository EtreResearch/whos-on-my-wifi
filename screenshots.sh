#!/bin/sh
# Regenerates docs/screenshots/*.png from made-up data (no real network involved).
set -eu
cd "$(dirname "$0")"
mkdir -p build/module-cache build/shots docs/screenshots
sed '/^@main$/d' Sources/WiFiMonitor.swift > build/shots/ui.swift
cp Tests/screenshots.swift build/shots/main.swift
swiftc -swift-version 5 -module-cache-path build/module-cache \
    Sources/Discovery.swift Sources/History.swift Sources/Sightings.swift build/shots/ui.swift build/shots/main.swift \
    -o build/shots/render
build/shots/render
