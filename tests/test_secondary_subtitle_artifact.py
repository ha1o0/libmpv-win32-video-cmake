"""Validate stale DLL rejection and the production CMake packaging dependency."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from verify_secondary_subtitle_artifact import REQUIRED_OPTIONS, verify


REPO = Path(__file__).resolve().parents[1]


class SecondarySubtitleArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mpv-secondary-artifact-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.library = self.root / 'libmpv-2.dll'

    def test_each_required_option_is_mandatory(self):
        for missing in REQUIRED_OPTIONS:
            self.library.write_bytes(b'MZ' + b''.join(
                option for option in REQUIRED_OPTIONS if option != missing))
            with self.subTest(option=missing), self.assertRaisesRegex(ValueError, 'missing'):
                verify(self.library)
        self.library.write_bytes(b'MZ' + b''.join(REQUIRED_OPTIONS))
        verify(self.library)

    def test_non_windows_artifacts_are_rejected(self):
        self.library.write_bytes(b''.join(REQUIRED_OPTIONS))
        with self.assertRaisesRegex(ValueError, 'Windows PE'):
            verify(self.library)

    @unittest.skipUnless(shutil.which('cmake') and shutil.which('ninja'), 'requires CMake and Ninja')
    def test_production_step_blocks_stripping_until_verification_passes(self):
        recipe = (REPO / 'packages/mpv.cmake').read_text()
        steps = recipe[recipe.index('ExternalProject_Add_Step(mpv verify-secondary-subtitle-style'):
                       recipe.index('ExternalProject_Add_Step(mpv copy-binary')]
        self.library.write_bytes(b'MZstale')
        stripped = self.root / 'stripped'
        (self.root / 'CMakeLists.txt').write_text('''cmake_minimum_required(VERSION 3.19)
project(subtitle_check NONE)
include(ExternalProject)
cmake_policy(SET CMP0114 NEW)
set(PROJECT_SOURCE_DIR "{repo}")
set(mpv_add_debuglink COMMAND ${{CMAKE_COMMAND}} -E touch "{stripped}")
ExternalProject_Add(mpv
 SOURCE_DIR "{root}/source"
 DOWNLOAD_COMMAND "" UPDATE_COMMAND "" CONFIGURE_COMMAND "" INSTALL_COMMAND ""
 BUILD_COMMAND ${{CMAKE_COMMAND}} -E copy "{library}" <BINARY_DIR>/libmpv-2.dll)
'''.format(repo=REPO, root=self.root, library=self.library, stripped=stripped) + steps)
        build = self.root / 'build'
        configured = subprocess.run(['cmake', '-S', str(self.root), '-B', str(build), '-G', 'Ninja'],
                                    capture_output=True, text=True, timeout=30)
        self.assertEqual(configured.returncode, 0, configured.stdout + configured.stderr)
        def run_build():
            return subprocess.run(['cmake', '--build', str(build), '--target', 'mpv'],
                                  capture_output=True, text=True, timeout=30)
        failed = run_build()
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn('missing:', failed.stdout + failed.stderr)
        self.assertFalse(stripped.exists())
        # Replace the built fixture just as a rebuild would. The always-on
        # verifier must now allow the existing downstream packaging step.
        built_library = build / 'mpv-prefix/src/mpv-build/libmpv-2.dll'
        built_library.write_bytes(b'MZ' + b''.join(REQUIRED_OPTIONS))
        passed = run_build()
        self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)
        self.assertTrue(stripped.exists())


if __name__ == '__main__':
    unittest.main()
