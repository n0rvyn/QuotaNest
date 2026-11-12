#!/usr/bin/env python3
"""Package only public source files for developers."""
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
print(f'{checksum}  {out.name}')
print(f'Packaged {len(files)} public files; private development files excluded.')
