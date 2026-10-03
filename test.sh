#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p build/module-cache
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Discovery.swift Sources/History.swift Sources/Sightings.swift Tests/main.swift -o build/discovery-check
build/discovery-check "$@"
