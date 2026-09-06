#!/bin/zsh
# Headless test of the Mind core (embed → store → link). No app launch.
set -e
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O -o build/test-mind Engine/Core/Log.swift Engine/Mind/Embed.swift Engine/Mind/Store.swift Engine/Mind/Link.swift Engine/Mind/Tasks.swift tools/test-mind/main.swift -framework Foundation -framework NaturalLanguage 2>&1 | grep -E "error" && exit 1
./build/test-mind
