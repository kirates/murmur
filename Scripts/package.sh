#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.dist/Murmur.app"

"$ROOT/Scripts/build-app.sh" >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="$ROOT/.dist/Murmur-$VERSION.zip"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

codesign --verify --strict "$APP"
echo "$ZIP"
