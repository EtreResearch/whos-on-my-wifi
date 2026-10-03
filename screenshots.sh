#!/bin/sh
# Regenerates the README screenshots (made-up data, no real network) and the app icon.
set -eu
cd "$(dirname "$0")"
mkdir -p build/module-cache build/shots docs/screenshots
sed '/^@main$/d' Sources/WiFiMonitor.swift > build/shots/ui.swift
cp Tests/screenshots.swift build/shots/main.swift
swiftc -swift-version 5 -module-cache-path build/module-cache \
    Sources/Discovery.swift Sources/History.swift Sources/Sightings.swift build/shots/ui.swift build/shots/main.swift \
    -o build/shots/render
build/shots/render
mkdir -p build/shots/icon && cp Tests/icon.swift build/shots/icon/main.swift
swiftc -swift-version 5 -module-cache-path build/module-cache build/shots/icon/main.swift -o build/shots/icon-render
build/shots/icon-render
iconutil -c icns build/shots/AppIcon.iconset -o AppIcon.icns
echo "Wrote AppIcon.icns and docs/icon.png"
