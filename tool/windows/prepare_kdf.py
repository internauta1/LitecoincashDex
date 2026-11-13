"""Provision the exact approved KDF bytes; never execute the binary."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def verify(path, lock):
    if path.is_symlink() or not path.is_file() or path.stat().st_size != lock['size']:
        raise ValueError('KDF identity/size mismatch')
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest().upper()
    if digest != lock['sha256']:
        raise ValueError('KDF SHA-256 mismatch; no fallback permitted')
    return digest


def allowed_url(url, lock=None):
    parsed = urllib.parse.urlsplit(url)
    safe = (parsed.scheme == 'https' and parsed.hostname == 'github.com'
            and not parsed.username and not parsed.password and not parsed.query
            and not parsed.fragment and parsed.port in (None, 443))
    project = any(parsed.path.startswith('/internauta1/'+repo+'/releases/download/')
                  for repo in ('LitecoincashDex', 'litecoincashdex-desktop'))
    upstream = bool(lock and url == lock.get('upstreamArchiveUrl')
                    and parsed.path.startswith('/GLEECBTC/komodo-defi-framework/releases/download/'))
    return safe and (project or upstream)


def extract_upstream(archive, output, lock):
    """Read only the pinned member of the pinned official ZIP; never extract paths."""
    archive_lock = {'size': lock['upstreamArchiveSize'],
                    'sha256': lock['upstreamArchiveSha256']}
    verify(archive, archive_lock)
    with zipfile.ZipFile(archive) as package:
        matches = [x for x in package.infolist()
                   if x.filename == lock['upstreamArchiveExecutable']]
        if len(matches) != 1:
            raise ValueError('Official archive must contain one pinned engine')
        entry = matches[0]
        if (entry.is_dir() or entry.file_size != lock['size'] or entry.flag_bits & 1
                or (entry.external_attr >> 16) & 0o170000 == 0o120000):
            raise ValueError('Invalid official engine archive member')
        with package.open(entry) as source, output.open('xb') as target:
            total = 0
            while chunk := source.read(1024 * 1024):
                total += len(chunk)
                if total > lock['size']:
                    raise ValueError('Official engine exceeds pinned size')
                target.write(chunk)
    verify(output, lock)


def provision(root, source=None, url=None, upstream_archive=None):
    lock = json.loads((root / 'artifacts/kdf/windows.lock.json').read_text(encoding='utf-8'))
    target = root / 'artifacts/kdf/windows/mm2_lccnext_8762.exe'
    if target.exists():
        verify(target, lock)
        return target
    if sum(bool(x) for x in (source, url, upstream_archive)) != 1:
        raise ValueError('Provide one explicit KDF file, official ZIP or approved public release URL')
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix('.download')
    download = target.with_suffix('.upstream-download')
    if temporary.exists() or download.exists():
        raise ValueError('Previous incomplete KDF download requires review')
    try:
        if source:
            source = Path(source).resolve()
            verify(source, lock)
            shutil.copyfile(source, temporary)
        elif upstream_archive:
            extract_upstream(Path(upstream_archive), temporary, lock)
        else:
            if not allowed_url(url, lock):
                raise ValueError('Only approved project releases or the exact pinned upstream ZIP are allowed')
            is_archive = url == lock.get('upstreamArchiveUrl')
            destination = download if is_archive else temporary
            limit = lock['upstreamArchiveSize'] if is_archive else lock['size']
            request = urllib.request.Request(url, headers={'User-Agent': 'LitecoinCashDEXNext-build'})
            with urllib.request.urlopen(request, timeout=60) as response, destination.open('xb') as output:
                total = 0
                while chunk := response.read(1024*1024):
                    total += len(chunk)
                    if total > limit:
                        raise ValueError('Download exceeds pinned KDF size')
                    output.write(chunk)
            if is_archive:
                extract_upstream(download, temporary, lock)
        verify(temporary, lock)
        temporary.replace(target)
    finally:
        if temporary.exists():
            temporary.unlink()
        if download.exists():
            download.unlink()
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--file', type=Path)
    parser.add_argument('--url')
    parser.add_argument('--upstream-archive', type=Path)
    args = parser.parse_args()
    path = provision(ROOT, args.file, args.url, args.upstream_archive)
    print('Verified KDF cache: '+str(path))


if __name__ == '__main__':
    main()
