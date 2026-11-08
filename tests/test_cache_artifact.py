import tempfile
import unittest
from pathlib import Path
from verify_cache_artifact import REQUIRED, verify


class CacheArtifactTests(unittest.TestCase):
    def test_missing_features_and_non_pe_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / 'libmpv-2.dll'
            for data in (b'MZ', b'MZ' + REQUIRED[0], b'MZ' + REQUIRED[1], b''.join(REQUIRED)):
                library.write_bytes(data)
                with self.assertRaises(ValueError):
                    verify(library)
            library.write_bytes(b'MZ' + b''.join(REQUIRED))
            verify(library)


if __name__ == '__main__':
    unittest.main()
