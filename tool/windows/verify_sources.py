"""Verify vendored SDK/static assets against the reviewed source manifest."""
from pathlib import Path, PurePosixPath
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]


def main():
    entries = json.loads((ROOT / 'SDK_SOURCE_MANIFEST.json').read_text(encoding='utf-8'))
    for entry in entries:
        name = PurePosixPath(entry['path'])
        if name.is_absolute() or '..' in name.parts or name.parts[0] != 'sdk':
            raise ValueError('Invalid SDK manifest path')
        path = ROOT / name
        if path.is_symlink() or not path.resolve().is_relative_to(ROOT.resolve()):
            raise ValueError('Redirected SDK source')
        if hashlib.sha256(path.read_bytes()).hexdigest().upper() != entry['sha256']:
            raise ValueError('Reviewed SDK source changed: '+str(name))
    print(f'Verified {len(entries)} vendored SDK/static source files')


if __name__ == '__main__':
    main()
