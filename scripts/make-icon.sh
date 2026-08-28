#!/usr/bin/env bash
#
# Redraws Resources/AppIcon.icns.
#
# Compiled rather than run with `swift scripts/...`, because the renderer draws
# the app's own mark: the source of that path is RephrazeKit/UI/RephrazeMark.swift
# and the interpreter takes only one file. One definition, four places it shows up.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build

swiftc -O -o build/make-icon \
  Sources/RephrazeKit/UI/RephrazeMark.swift \
  scripts/icon/main.swift

./build/make-icon
