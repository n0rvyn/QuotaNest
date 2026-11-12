#!/usr/bin/env python3
"""Generate a cask only for a downloaded, checksum-verified public release asset."""
import argparse
import hashlib
import re
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('repository', help='Verified public GitHub OWNER/REPO')
p.add_argument('version')
p.add_argument('archive', type=Path)
p.add_argument('output', type=Path)
a = p.parse_args()
if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', a.repository):
    p.error('repository must be OWNER/REPO')
if not re.fullmatch(r'\d+\.\d+\.\d+', a.version):
    p.error('version must be X.Y.Z')
if a.archive.name != f'QuotaNest-{a.version}-macos.zip':
    p.error('archive name does not match release version')
checksum = hashlib.sha256(a.archive.read_bytes()).hexdigest()
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(f'''cask "quotanest" do
  version "{a.version}"
  sha256 "{checksum}"

  url "https://github.com/{a.repository}/releases/download/v#{{version}}/QuotaNest-#{{version}}-macos.zip"
  name "QuotaNest"
  desc "Menu bar monitor for AI resource and subscription quotas"
  homepage "https://github.com/{a.repository}"

  depends_on macos: ">= :sonoma"

  app "QuotaNest.app"
end
''')
print(a.output)
