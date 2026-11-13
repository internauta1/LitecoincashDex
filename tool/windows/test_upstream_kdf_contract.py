"""Synthetic archive/security tests; no process or external network is used."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import io
import warnings
import zipfile

spec = importlib.util.spec_from_file_location('prepare_upstream', Path(__file__).with_name('prepare_kdf.py'))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class UpstreamArtifactTests(unittest.TestCase):
    def fixture(self, folder, members=None):
        root = Path(folder)
        engine = b'synthetic-non-executable-upstream'
        archive = root / 'official.zip'
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(archive, 'w') as z:
                for name, data in members if members is not None else [('mm2.exe', engine), ('../ignored.dll', b'unused')]:
                    z.writestr(name, data)
        lock = {'size': len(engine), 'sha256': hashlib.sha256(engine).hexdigest().upper(),
                'upstreamArchiveSize': archive.stat().st_size,
                'upstreamArchiveSha256': hashlib.sha256(archive.read_bytes()).hexdigest().upper(),
                'upstreamArchiveExecutable': 'mm2.exe',
                'upstreamArchiveUrl': 'https://github.com/GLEECBTC/komodo-defi-framework/releases/download/v2.4.0-beta/mm2-c800ea03f-Win64.zip'}
        config = root / 'artifacts/kdf/windows.lock.json'
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps(lock), encoding='utf-8')
        return root, archive, engine, lock

    def test_extracts_only_verified_engine_without_extracting_archive_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            root, archive, engine, lock = self.fixture(folder)
            output = prepare.provision(root, upstream_archive=archive)
            self.assertEqual(output.read_bytes(), engine)
            self.assertEqual(prepare.verify(output, lock), lock['sha256'])
            self.assertFalse((root / 'ignored.dll').exists())
            self.assertEqual([p.name for p in output.parent.iterdir()], [output.name])

    def test_modified_archive_is_refused_before_extraction(self):
        with tempfile.TemporaryDirectory() as folder:
            root, archive, _, _ = self.fixture(folder)
            data = bytearray(archive.read_bytes()); data[20] ^= 1; archive.write_bytes(data)
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                prepare.provision(root, upstream_archive=archive)
            self.assertEqual(list((root / 'artifacts/kdf/windows').iterdir()), [])

    def test_missing_or_duplicate_engine_is_refused(self):
        for members in [[('other.exe', b'x')], [('mm2.exe', b'x'), ('mm2.exe', b'y')]]:
            with self.subTest(members=members), tempfile.TemporaryDirectory() as folder:
                root, archive, _, _ = self.fixture(folder, members)
                with self.assertRaisesRegex(ValueError, 'one pinned engine'):
                    prepare.provision(root, upstream_archive=archive)

    def test_same_size_wrong_engine_is_refused_and_partial_removed(self):
        with tempfile.TemporaryDirectory() as folder:
            engine = b'synthetic-non-executable-upstream'
            root, archive, _, _ = self.fixture(folder, [('mm2.exe', b'X' * len(engine))])
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                prepare.provision(root, upstream_archive=archive)
            self.assertEqual(list((root / 'artifacts/kdf/windows').iterdir()), [])

    def test_redirected_archive_member_is_refused(self):
        entry = zipfile.ZipInfo('mm2.exe')
        entry.create_system = 3
        entry.external_attr = (0o120777 << 16)
        with tempfile.TemporaryDirectory() as folder:
            root, archive, _, _ = self.fixture(folder, [(entry, b'synthetic-non-executable-upstream')])
            with self.assertRaisesRegex(ValueError, 'Invalid official'):
                prepare.provision(root, upstream_archive=archive)

    def test_explicit_sources_cannot_be_combined(self):
        with tempfile.TemporaryDirectory() as folder:
            root, archive, _, _ = self.fixture(folder)
            with self.assertRaisesRegex(ValueError, 'one explicit'):
                prepare.provision(root, source=archive, upstream_archive=archive)

    def test_explicit_official_url_verifies_archive_and_engine(self):
        with tempfile.TemporaryDirectory() as folder:
            root, archive, engine, lock = self.fixture(folder)
            with patch.object(prepare.urllib.request, 'urlopen', return_value=io.BytesIO(archive.read_bytes())):
                output = prepare.provision(root, url=lock['upstreamArchiveUrl'])
            self.assertEqual(output.read_bytes(), engine)
            self.assertEqual([p.name for p in output.parent.iterdir()], [output.name])

    def test_download_larger_than_pin_is_refused_and_cleaned_up(self):
        with tempfile.TemporaryDirectory() as folder:
            root, archive, _, lock = self.fixture(folder)
            with patch.object(prepare.urllib.request, 'urlopen', return_value=io.BytesIO(archive.read_bytes()+b'X')):
                with self.assertRaisesRegex(ValueError, 'exceeds pinned'):
                    prepare.provision(root, url=lock['upstreamArchiveUrl'])
            self.assertEqual(list((root / 'artifacts/kdf/windows').iterdir()), [])

    def test_wrong_member_size_is_refused_before_writing(self):
        with tempfile.TemporaryDirectory() as folder:
            root, archive, _, _ = self.fixture(folder, [('mm2.exe', b'too short')])
            with self.assertRaisesRegex(ValueError, 'Invalid official'):
                prepare.provision(root, upstream_archive=archive)

    def test_pending_download_is_preserved_for_review(self):
        with tempfile.TemporaryDirectory() as folder:
            root, archive, _, _ = self.fixture(folder)
            directory = root/'artifacts/kdf/windows'; directory.mkdir()
            pending = directory/'mm2_lccnext_8762.upstream-download'; pending.write_bytes(b'pending')
            with self.assertRaisesRegex(ValueError, 'incomplete'):
                prepare.provision(root, upstream_archive=archive)
            self.assertEqual(pending.read_bytes(), b'pending')

    def test_only_exact_https_upstream_archive_is_allowed(self):
        with tempfile.TemporaryDirectory() as folder:
            _, _, _, lock = self.fixture(folder)
            url = lock['upstreamArchiveUrl']
            self.assertTrue(prepare.allowed_url(url, lock))
            for other in [url.replace('v2.4.0-beta', 'latest'), url+'?token=x', url+'#fragment',
                          url.replace('https:', 'http:'), url.replace('github.com', 'github.com.evil.test'),
                          url.replace('github.com', 'user:password@github.com')]:
                self.assertFalse(prepare.allowed_url(other, lock))
            self.assertFalse(prepare.allowed_url(url))

    def test_build_layers_pin_the_same_new_engine(self):
        root = Path(__file__).resolve().parents[2]
        lock = json.loads((root/'artifacts/kdf/windows.lock.json').read_text(encoding='utf-8'))
        self.assertEqual(lock['embeddedSourceCommit'], 'c800ea03f12dab33d2dc04a1d858ee6da111203f')
        self.assertEqual(lock['sha256'], 'FB641F1DF1CEB46D7C26F71BCA6BED12ACC07DEB188C7A96F93D20DF61B24AB2')
        self.assertIn(lock['sha256'].lower(), (root/'windows/CMakeLists.txt').read_text(encoding='utf-8'))
        self.assertIn(lock['sha256'], (root/'tool/windows/build.ps1').read_text(encoding='utf-8'))
        self.assertFalse((root/'docs/publication/KDF-COMMUNITY.patch').exists())


if __name__ == '__main__':
    unittest.main()
