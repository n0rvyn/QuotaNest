#!/usr/bin/env python3
"""Package only public source files and generate the matching Homebrew formula."""
from pathlib import Path
import gzip
import hashlib
import io
import tarfile

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text().strip()
paths = ['Package.swift', 'VERSION', 'README.md', '.gitignore', 'Sources', 'Tests', 'Assets', 'scripts']
files = []
for name in paths:
    p = root / name
    files.extend(sorted(f for f in p.rglob('*') if f.is_file()) if p.is_dir() else [p])
files = [p for p in files if not any(part in {'__pycache__', '.DS_Store'} for part in p.relative_to(root).parts)]
secrets = []
if (root / '.env').exists():
    for line in (root / '.env').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            value = line.split('=', 1)[1].strip().strip('\"\'')
            if value:
                secrets.append(value.encode())
for p in files:
    if p.is_symlink() or any(secret in p.read_bytes() for secret in secrets):
        raise SystemExit(f'Unsafe public source: {p.relative_to(root)}')
out = root / 'dist' / f'QuotaNest-{version}-source.tar.gz'
out.parent.mkdir(exist_ok=True)
with out.open('wb') as stream, gzip.GzipFile(filename='', mode='wb', fileobj=stream, mtime=0) as compressed:
    with tarfile.open(fileobj=compressed, mode='w') as archive:
        for p in files:
            data = p.read_bytes()
            info = tarfile.TarInfo(f'QuotaNest-{version}/{p.relative_to(root)}')
            info.size = len(data)
            info.mode = 0o755 if p.stat().st_mode & 0o111 else 0o644
            archive.addfile(info, io.BytesIO(data))
checksum = hashlib.sha256(out.read_bytes()).hexdigest()
formula = root / 'Formula' / 'quotanest.rb'
formula.parent.mkdir(exist_ok=True)
formula.write_text(f'''class Quotanest < Formula
  desc "Native macOS menu bar monitor for Volcengine Ark quotas"
  homepage "https://github.com/n0rvyn/QuotaNest"
  url "https://github.com/n0rvyn/QuotaNest/releases/download/v{version}/QuotaNest-{version}-source.tar.gz"
  sha256 "{checksum}"
  version "{version}"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sonoma

  def install
    ENV["QUOTANEST_NO_PACKAGE_SANDBOX"] = "1"
    system "./scripts/build-app.sh"
    prefix.install "dist/QuotaNest.app"
    bin.install_symlink prefix/"QuotaNest.app/Contents/MacOS/QuotaNest" => "quotanest"
  end

  def caveats
    <<~EOS
      Launch QuotaNest:
        open "#{{opt_prefix}}/QuotaNest.app"
      Enter your Ark Access Key and Secret Key in Settings. Credentials stay in macOS Keychain.
    EOS
  end

  test do
    assert_match "QuotaNest", shell_output("#{{bin}}/quotanest --help")
    assert_equal version.to_s, shell_output("#{{bin}}/quotanest --version").strip
  end
end
''')
print(f'{checksum}  {out.name}')
print(f'Packaged {len(files)} public files; private development files excluded.')
