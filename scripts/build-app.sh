#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift_flags=()
if [[ "${QUOTANEST_NO_PACKAGE_SANDBOX:-0}" == "1" ]]; then swift_flags+=(--disable-sandbox); fi
for architecture in arm64 x86_64; do
  swift build -c release --arch "$architecture" "${swift_flags[@]}" --cache-path .build/cache --config-path .build/config --security-path .build/security
done
mkdir -p dist
app='dist/QuotaNest.app'
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create .build/arm64-apple-macosx/release/QuotaNest .build/x86_64-apple-macosx/release/QuotaNest -output "$app/Contents/MacOS/QuotaNest"
cp Assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
python3 - "$app" "$(cat VERSION)" <<'PLIST'
import plistlib,sys
from pathlib import Path
info = dict(CFBundleExecutable='QuotaNest', CFBundleIdentifier='com.norvyn.QuotaNest',
    CFBundleIconFile='AppIcon', CFBundleName='QuotaNest', CFBundleDisplayName='QuotaNest',
    CFBundlePackageType='APPL', CFBundleShortVersionString=sys.argv[2], CFBundleVersion='1',
    LSMinimumSystemVersion='14.0', LSUIElement=True, NSHighResolutionCapable=True)
with (Path(sys.argv[1])/'Contents/Info.plist').open('wb') as f:
    plistlib.dump(info, f)
PLIST
codesign --force --sign - "$app"
codesign --verify --strict "$app"
archive="dist/QuotaNest-$(cat VERSION)-macos.zip"
ditto -c -k --keepParent "$app" "$archive"
shasum -a 256 "$archive"
