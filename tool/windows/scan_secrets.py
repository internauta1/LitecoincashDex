"""Pinned scanner, redacted output, exact-hash reviewed fixture exceptions only."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ZIP_SHA256 = 'D29144DEFF3A68AA93CED33DDDF84B7FDC26070ADD4AA0F4513094C8332AFC4E'
URL = 'https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_windows_x64.zip'


def reviewed(finding, root, manifest):
    name = finding['File'].replace('\\', '/')
    path = root / name
    if not path.resolve().is_relative_to(root.resolve()) or not path.is_file():
        return False
    commit = finding.get('Commit')
    if commit:
        if not re.fullmatch('[0-9a-fA-F]{40}', commit):
            return False
        historical = subprocess.run(['git', '-C', str(root), 'show', commit+':'+name],
                                    capture_output=True)
        if historical.returncode != 0:
            return False
        content = historical.stdout
    else:
        content = path.read_bytes()
    sha = hashlib.sha256(content).hexdigest().upper()
    return any(item['path'] == name and item['rule'] == finding['RuleID']
               and item['line'] == finding['StartLine'] and item['sourceSha256'] == sha
               for item in manifest['reviewedFindings'])


def scanner(folder):
    folder.mkdir(parents=True, exist_ok=True)
    archive = folder / 'gitleaks-8.30.1.zip'
    if not archive.exists():
        with urllib.request.urlopen(URL, timeout=60) as response, archive.open('xb') as out:
            while chunk := response.read(1024*1024):
                out.write(chunk)
    if hashlib.sha256(archive.read_bytes()).hexdigest().upper() != ZIP_SHA256:
        raise ValueError('Scanner archive checksum mismatch')
    with zipfile.ZipFile(archive) as package:
        data = package.read('gitleaks.exe')
    executable = folder / 'gitleaks.exe'
    executable.write_bytes(data)
    return executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged', action='store_true')
    args = parser.parse_args()
    work = ROOT / '.audit-tools'
    executable = scanner(work)
    report = work / 'redacted-findings.json'
    command = [str(executable), 'git', str(ROOT), '--redact=100', '--no-banner',
               '--report-format', 'json', '--report-path', str(report)]
    command += ['--staged'] if args.staged else ['--log-opts=--all']
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode not in (0, 1):
        raise RuntimeError('Scanner could not complete; publication remains blocked')
    findings = json.loads(report.read_text(encoding='utf-8-sig')) if report.exists() else []
    manifest = json.loads((ROOT / 'PUBLIC_SECRET_REVIEW.json').read_text(encoding='utf-8'))
    unreviewed = [f for f in findings if not reviewed(f, ROOT, manifest)]
    print(json.dumps({'scanner': 'gitleaks 8.30.1', 'findings': len(findings),
                      'exactHashReviewed': len(findings)-len(unreviewed),
                      'unreviewed': [{'path': f['File'], 'rule': f['RuleID'],
                                      'line': f['StartLine']} for f in unreviewed]}, indent=2))
    if unreviewed:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
