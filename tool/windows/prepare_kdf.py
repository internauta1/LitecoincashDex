"""Provision the exact approved KDF bytes; never execute the binary."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]


def verify(path, lock):
    if path.is_symlink() or not path.is_file() or path.stat().st_size != lock['size']:
        raise ValueError('KDF identity/size mismatch')
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest().upper()
    if digest != lock['sha256']:
        raise ValueError('KDF SHA-256 mismatch; no fallback permitted')
    return digest


def allowed_url(url):
    parsed = urllib.parse.urlsplit(url)
    return (parsed.scheme == 'https' and parsed.hostname == 'github.com'
            and not parsed.username and not parsed.password and not parsed.query
            and any(parsed.path.startswith('/internauta1/'+repo+'/releases/download/')
                    for repo in ('LitecoincashDex', 'litecoincashdex-desktop')))


def provision(root, source=None, url=None):
    lock = json.loads((root / 'artifacts/kdf/windows.lock.json').read_text())
    target = root / 'artifacts/kdf/windows/mm2_lccnext_8762.exe'
    if target.exists():
        verify(target, lock)
        return target
    if bool(source) == bool(url):
        raise ValueError('Provide one explicit KDF file or approved public release URL')
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix('.download')
    if temporary.exists():
        raise ValueError('Previous incomplete KDF download requires review')
    try:
        if source:
            source = Path(source).resolve()
            verify(source, lock)
            shutil.copyfile(source, temporary)
        else:
            if not allowed_url(url):
                raise ValueError('Only this project public GitHub release URLs are allowed')
            request = urllib.request.Request(url, headers={'User-Agent': 'LitecoinCashDEXNext-build'})
            with urllib.request.urlopen(request, timeout=60) as response, temporary.open('xb') as output:
                total = 0
                while chunk := response.read(1024*1024):
                    total += len(chunk)
                    if total > lock['size']:
                        raise ValueError('Download exceeds pinned KDF size')
                    output.write(chunk)
        verify(temporary, lock)
        temporary.replace(target)
    finally:
        if temporary.exists():
            temporary.unlink()
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--file', type=Path)
    parser.add_argument('--url')
    args = parser.parse_args()
    path = provision(ROOT, args.file, args.url)
    print('Verified KDF cache: '+str(path))


if __name__ == '__main__':
    main()
