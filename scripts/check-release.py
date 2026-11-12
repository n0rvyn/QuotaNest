#!/usr/bin/env python3
"""Inspect the exact archive without exposing credentials to output."""
import argparse
import plistlib
import zipfile
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('archive', type=Path)
p.add_argument('--credential-file', type=Path)
a = p.parse_args()
secrets = []
if a.credential_file:
    for line in a.credential_file.read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            value = line.split('=', 1)[1].strip().strip('\"\'')
            if value:
                secrets.append(value.encode())
with zipfile.ZipFile(a.archive) as z:
    names = z.namelist()
    if any(not name.startswith('QuotaNest.app/') for name in names):
        raise SystemExit('Unexpected archive root')
    if any('.env' in name or name.lower().endswith('.pdf') for name in names):
        raise SystemExit('Private development file in release')
    info = plistlib.loads(z.read('QuotaNest.app/Contents/Info.plist'))
    assert info['CFBundleIdentifier'] == 'com.norvyn.QuotaNest'
    assert info['CFBundleExecutable'] == 'QuotaNest'
    assert info['CFBundleIconFile'] == 'AppIcon'
    assert z.read('QuotaNest.app/Contents/Resources/AppIcon.icns').startswith(b'icns')
    assert info['LSMinimumSystemVersion'] == '14.0'
    assert info['LSUIElement'] is True
    for name in names:
        if any(secret in z.read(name) for secret in secrets):
            raise SystemExit('Credential material found in archive; do not publish')
print('Archive metadata and credential exclusion passed')
# The future public source tree must exclude the supplied private files.
for directory in [Path('Sources'), Path('Tests'), Path('scripts'), Path('.github'), Path('docs')]:
    for file in directory.rglob('*'):
        if file.is_file() and any(secret in file.read_bytes() for secret in secrets):
            raise SystemExit('Credential material found in source; do not publish')
print('Source credential exclusion passed')
