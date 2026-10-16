#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build outputs
SDK="$(xcrun --sdk macosx --show-sdk-path)"
COMMON=(-swift-version 5 -parse-as-library -sdk "$SDK" -framework AppKit -framework AVFoundation -framework QuartzCore -framework CryptoKit)
if [[ "${1:-}" == "test" ]]; then
  xcrun swiftc "${COMMON[@]}" Core.swift Media.swift Tests.swift -o build/tests
  ./build/tests
  exit 0
fi
APP="build/元点剪辑批量工具箱.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
for ARCH in arm64 x86_64; do
  xcrun swiftc "${COMMON[@]}" -O -target "$ARCH-apple-macos13.0" Core.swift Media.swift App.swift Views.swift -o "build/yuandian-$ARCH"
done
lipo -create build/yuandian-arm64 build/yuandian-x86_64 -output "$APP/Contents/MacOS/YuandianToolbox"
lipo -verify_arch arm64 x86_64 "$APP/Contents/MacOS/YuandianToolbox"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" AppIcon.png --out "build/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" AppIcon.png --out "build/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
cp README.md "$APP/Contents/Resources/使用说明.md"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/YuandianToolbox" --ui-smoke "$PWD/build/ui-smoke"
ditto -c -k --sequesterRsrc --keepParent "$APP" outputs/YuandianToolbox-macOS-universal.zip
mkdir -p build/dmg
cp -R "$APP" build/dmg/
ln -sfn /Applications build/dmg/Applications
cp README.md build/dmg/使用说明.md
hdiutil create -volname "元点剪辑批量工具箱" -srcfolder build/dmg -ov -format UDZO outputs/YuandianToolbox-macOS-universal.dmg
(cd outputs && shasum -a 256 *.zip *.dmg > SHA256SUMS.txt)
