#!/bin/zsh
# Headless check of the screen saver: load the bundle, animate, render a frame to build/saver-frame.png.
set -e
cd "$(dirname "$0")/.."
./make-saver.sh >/dev/null
swiftc -O -o build/test-saver tools/test-saver/main.swift -framework AppKit -framework ScreenSaver 2>&1 | grep -E "error" && exit 1
./build/test-saver build/PixelPet.saver
