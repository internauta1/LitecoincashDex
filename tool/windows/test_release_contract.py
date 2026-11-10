import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('prepare', Path(__file__).with_name('prepare_kdf.py'))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)
scan_spec = importlib.util.spec_from_file_location('scan', Path(__file__).with_name('scan_secrets.py'))
scan = importlib.util.module_from_spec(scan_spec)
scan_spec.loader.exec_module(scan)


class ArtifactContractTests(unittest.TestCase):
    def fixture(self, folder):
        root = Path(folder)
        data = b'offline-test-engine-bytes'
        lock = {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest().upper()}
        config = root / 'artifacts/kdf/windows.lock.json'
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps(lock))
        binary = root / 'fixture.exe'
        binary.write_bytes(data)
        return root, binary, lock

    def test_copies_exact_bytes_without_executing_them(self):
        with tempfile.TemporaryDirectory() as folder:
            root, binary, lock = self.fixture(folder)
            output = prepare.provision(root, source=binary)
            self.assertEqual(output.read_bytes(), binary.read_bytes())
            self.assertEqual(prepare.verify(output, lock), lock['sha256'])

    def test_same_length_tampering_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root, binary, lock = self.fixture(folder)
            binary.write_bytes(b'X' * lock['size'])
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                prepare.provision(root, source=binary)
            self.assertFalse((root / 'artifacts/kdf/windows/mm2_lccnext_8762.exe').exists())

    def test_corrupted_cache_cannot_silently_use_another_source(self):
        with tempfile.TemporaryDirectory() as folder:
            root, binary, lock = self.fixture(folder)
            output = prepare.provision(root, source=binary)
            output.write_bytes(b'X'*lock['size'])
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                prepare.provision(root, source=binary)

    def test_engine_is_required_not_downloaded_implicitly(self):
        with tempfile.TemporaryDirectory() as folder:
            root, _, _ = self.fixture(folder)
            with self.assertRaisesRegex(ValueError, 'explicit'):
                prepare.provision(root)

    def test_source_urls_are_restricted_to_project_public_releases(self):
        self.assertTrue(prepare.allowed_url('https://github.com/internauta1/LitecoincashDex/releases/download/v1/engine.exe'))
        for url in ('http://github.com/internauta1/LitecoincashDex/releases/download/v1/engine.exe',
                    'https://example.com/engine.exe', 'https://github.com/other/repo/releases/download/x/a',
                    'https://user:secret@github.com/internauta1/LitecoincashDex/releases/download/v1/a'):
            self.assertFalse(prepare.allowed_url(url))

    def test_secret_exception_rejects_any_source_change_or_new_location(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);path=root/'fixture.dart';path.write_bytes(b'synthetic fixture')
            sha=hashlib.sha256(path.read_bytes()).hexdigest().upper()
            finding={'File':'fixture.dart','RuleID':'generic-api-key','StartLine':1}
            manifest={'reviewedFindings':[{'path':'fixture.dart','rule':'generic-api-key','line':1,'sourceSha256':sha}]}
            self.assertTrue(scan.reviewed(finding,root,manifest))
            # A matching current file must never approve unknown historical bytes.
            historical={**finding,'Commit':'0'*40}
            self.assertFalse(scan.reviewed(historical,root,manifest))
            path.write_bytes(b'changed or newly added credential')
            self.assertFalse(scan.reviewed(finding,root,manifest))
            finding['StartLine']=2
            self.assertFalse(scan.reviewed(finding,root,manifest))


if __name__ == '__main__':
    unittest.main()
