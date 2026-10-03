#!/bin/sh
set -eu
cd "$(dirname "$0")"
app="build/Who's on My Wi-Fi.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/module-cache
for arch in arm64 x86_64; do
    swiftc -swift-version 5 -O -target "$arch-apple-macosx13.0" \
        -module-cache-path build/module-cache -parse-as-library \
        Sources/Discovery.swift Sources/History.swift Sources/Sightings.swift Sources/WiFiMonitor.swift \
        -o "build/WhosOnMyWiFi-$arch"
done
lipo -create build/WhosOnMyWiFi-arm64 build/WhosOnMyWiFi-x86_64 -output "$app/Contents/MacOS/WhosOnMyWiFi"
cp Info.plist "$app/Contents/Info.plist"
cp AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
if [ "${1:-}" = "--zip" ]; then
    rm -f build/WhosOnMyWiFi.zip
    ditto -c -k --norsrc --noextattr --noqtn --keepParent "$app" build/WhosOnMyWiFi.zip
    printf 'Zipped: %s/build/WhosOnMyWiFi.zip\n' "$PWD"
fi
printf 'Built: %s/%s\n' "$PWD" "$app"
