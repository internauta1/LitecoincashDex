"""NuGet build adapter: validate an already populated local package only.

There is deliberately no install, subprocess, download, or network fallback.
"""
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


def validate(args):
    if len(args) < 6 or args[0].lower() != 'install':
        raise ValueError('Only cached NuGet install checks are supported')
    name = args[1]
    version = args[args.index('-Version') + 1]
    output = Path(args[args.index('-OutputDirectory') + 1]).resolve()
    if name not in {
        'Microsoft.Windows.ImplementationLibrary',
        'Microsoft.Windows.CppWinRT', 'Microsoft.Web.WebView2', 'nlohmann.json',
    }:
        raise ValueError('Unexpected package')
    folder = output / (name if '-ExcludeVersion' in args else f'{name}.{version}')
    archive = folder / f'{folder.name}.nupkg'
    with zipfile.ZipFile(archive) as cached:
        nuspec = [n for n in cached.namelist() if n.endswith('.nuspec')]
        if len(nuspec) != 1:
            raise ValueError('Missing cached package manifest')
        document = ET.fromstring(cached.read(nuspec[0]))
        fields = {e.tag.rsplit('}', 1)[-1]: e.text for e in document.iter()}
        if fields.get('id') != name or fields.get('version') != version:
            raise ValueError('Cached package identity/version mismatch')
    if not (folder / 'build').is_dir():
        raise ValueError('Cached package headers/build inputs missing')
    return f'Offline package verified: {name} {version}'


if __name__ == '__main__':
    try:
        print(validate(sys.argv[1:]))
    except (ValueError, OSError, zipfile.BadZipFile, ET.ParseError):
        print('Offline package unavailable or invalid; network fallback refused', file=sys.stderr)
        sys.exit(1)
