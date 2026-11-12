#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift_flags=(--cache-path .build/cache --config-path .build/config --security-path .build/security)
if [[ "${QUOTANEST_NO_PACKAGE_SANDBOX:-0}" == "1" ]]; then swift_flags+=(--disable-sandbox); fi
for architecture in arm64 x86_64; do
  swift build -c release --arch "$architecture" "${swift_flags[@]}"
done
mkdir -p dist
app="${QUOTANEST_APP_DIR:-dist/QuotaNest.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create .build/arm64-apple-macosx/release/QuotaNest .build/x86_64-apple-macosx/release/QuotaNest -output "$app/Contents/MacOS/QuotaNest"
# SwiftPM can add its test-support toolchain directory when tests import the
# executable. It is not a distributable runtime path; remove it before signing.
python3 - "$app/Contents/MacOS/QuotaNest" <<'RPATH'
import re, subprocess, sys
binary = sys.argv[1]
commands = subprocess.check_output(['otool', '-arch', 'all', '-l', binary], text=True)
for path in sorted(set(re.findall(r'\bpath (.+?) \(offset \d+\)', commands))):
    if '/Toolchains/' in path and '/usr/lib/swift' in path:
        subprocess.run(['xcrun', 'install_name_tool', '-delete_rpath', path, binary], check=True)
RPATH
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
signing_identity="${QUOTANEST_SIGN_IDENTITY:--}"
signing_flags=(--force --sign "$signing_identity")
if [[ "$signing_identity" != "-" ]]; then signing_flags+=(--options runtime --timestamp); fi
codesign "${signing_flags[@]}" "$app"
codesign --verify --strict "$app"
archive="dist/QuotaNest-$(cat VERSION)-macos.zip"
ditto -c -k --keepParent "$app" "$archive"
shasum -a 256 "$archive"
