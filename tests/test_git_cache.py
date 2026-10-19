"""Exercise the generated cache-reset script against real local Git repositories.

Run with Python >= 3.8, CMake >= 3.24, Ninja and Git; no network or cross compiler
needed.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


def run(*args, cwd=None):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True,
                            timeout=60)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout.strip()


class GitCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mpv-git-cache-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.seed = self.root / "seed"
        self.seed.mkdir()
        run("git", "init", "-q", "-b", "main", cwd=self.seed)
        self.git_config(self.seed)
        (self.seed / "source.txt").write_text("upstream\n")
        run("git", "add", ".", cwd=self.seed)
        run("git", "commit", "-qm", "base", cwd=self.seed)
        self.base = run("git", "rev-parse", "HEAD", cwd=self.seed)
        self.remote = self.root / "remote.git"
        self.source = self.root / "source"
        run("git", "clone", "-q", "--bare", str(self.seed), str(self.remote))
        run("git", "clone", "-q", str(self.remote), str(self.source))
        self.git_config(self.source)
        self.build = self.root / "build"
        self.harness = self.root / "CMakeLists.txt"
        self.tag = "main"
        self.pin = ""
        self.executor = self.root / "exec"
        self.executor.write_text('#!/bin/bash\neval "$*"\n')
        self.executor.chmod(0o755)
        self.configure()
        self.stamp = self.build / "fixture-prefix/src/fixture-stamp"
        self.script = self.stamp / "reset_head.sh"
        self.populate()

    @staticmethod
    def git_config(path):
        run("git", "config", "user.name", "Cache test", cwd=path)
        run("git", "config", "user.email", "cache@example.invalid", cwd=path)

    def configure(self):
        self.harness.write_text(f'''cmake_minimum_required(VERSION 3.19)
project(cache_test NONE)
include(ExternalProject)
include("{REPO}/cmake/custom_steps.cmake")
cmake_policy(SET CMP0114 NEW)
set(EXEC "{self.executor}")
ExternalProject_Add(fixture
 GIT_REPOSITORY "{self.remote}"
 GIT_TAG "{self.tag}"
 SOURCE_DIR "{self.source}"
 UPDATE_COMMAND "" CONFIGURE_COMMAND "" BUILD_COMMAND "" INSTALL_COMMAND "")
set_property(TARGET fixture PROPERTY _EP_GIT_RESET "{self.pin}")
force_rebuild_git(fixture)
cleanup(fixture install)
ExternalProject_Add(archive SOURCE_DIR "{self.root}/archive"
 DOWNLOAD_COMMAND "" CONFIGURE_COMMAND "" BUILD_COMMAND "" INSTALL_COMMAND "")
cleanup(archive install)
''')
        run("cmake", "-S", str(self.root), "-B", str(self.build), "-G", "Ninja")

    def populate(self):
        self.stages = ["download", "update", "patch", "configure", "build",
                       "install", "postremovebuild"]
        # Model a completed cache created by the current lifecycle, including
        # its recorded source revision and recipe fingerprint.
        self.reset("--before-patch")
        for stage in self.stages:
            (self.stamp / ("fixture-" + stage)).touch()

    def reset(self, *args):
        return run("bash", str(self.script), *args)

    def assert_invalidated(self):
        for stage in self.stages:
            self.assertFalse((self.stamp / ("fixture-" + stage)).exists(), stage)

    def advance_remote(self):
        (self.seed / "source.txt").write_text("new upstream\n")
        run("git", "commit", "-qam", "advance", cwd=self.seed)
        run("git", "push", "-q", str(self.remote), "main", cwd=self.seed)
        run("git", "fetch", "-q", "origin", cwd=self.source)
        return run("git", "rev-parse", "HEAD", cwd=self.seed)

    def test_unchanged_complete_cache_preserves_stamps_and_source_mtime(self):
        source_file = self.source / "source.txt"
        os.utime(source_file, ns=(1000000000, 1000000000))
        self.assertEqual(self.reset(), "")
        self.assertEqual(source_file.stat().st_mtime_ns, 1000000000)
        for stage in self.stages:
            self.assertTrue((self.stamp / ("fixture-" + stage)).exists(), stage)

    def test_clean_but_incomplete_legacy_cache_is_rebuilt(self):
        (self.stamp / "RECIPE").unlink()
        (self.stamp / "fixture-postremovebuild").unlink()
        self.assertIn("legacy", self.reset())
        self.assert_invalidated()

    def test_complete_legacy_cache_without_recipe_is_rebuilt(self):
        (self.stamp / "RECIPE").unlink()
        self.assertIn("legacy", self.reset())
        self.assert_invalidated()

    def test_reset_of_configure_time_source_edits_invalidates_all_stages(self):
        (self.source / "source.txt").write_text("configure-time edit\n")
        self.assertIn("configure-time", self.reset())
        self.assertEqual((self.source / "source.txt").read_text(), "upstream\n")
        self.assert_invalidated()

    def test_cleanup_preserves_patch_commits_and_completed_stamps(self):
        (self.source / "source.txt").write_text("recipe patch\n")
        run("git", "commit", "-qam", "recipe patch", cwd=self.source)
        patched = run("git", "rev-parse", "HEAD", cwd=self.source)
        (self.source / "source.txt").write_text("temporary configure edit\n")
        self.reset("--cleanup")
        self.assertEqual(run("git", "rev-parse", "HEAD", cwd=self.source), patched)
        self.assertEqual((self.source / "source.txt").read_text(), "recipe patch\n")
        self.assertEqual(self.reset(), "")
        for stage in self.stages:
            self.assertTrue((self.stamp / ("fixture-" + stage)).exists(), stage)

    def test_before_patch_retires_old_patch_commit_without_deleting_dependencies(self):
        (self.source / "source.txt").write_text("recipe patch\n")
        run("git", "commit", "-qam", "old patch", cwd=self.source)
        self.reset("--before-patch")
        self.assertEqual(run("git", "rev-parse", "HEAD", cwd=self.source), self.base)
        self.assertEqual((self.stamp / "HEAD").read_text().strip(), self.base)
        self.assertTrue((self.stamp / "fixture-download").exists())

    def test_named_branch_advances_to_remote(self):
        new = self.advance_remote()
        self.reset()
        self.assertEqual(run("git", "rev-parse", "HEAD", cwd=self.source), new)
        self.assertEqual((self.stamp / "HEAD").read_text().strip(), new)
        self.assert_invalidated()

    def test_detached_pin_ignores_remote_advance(self):
        self.pin = self.base
        self.configure()
        self.reset()
        self.populate()
        run("git", "checkout", "-q", "--detach", self.base, cwd=self.source)
        self.advance_remote()
        self.assertEqual(self.reset(), "")
        self.assertTrue((self.stamp / "fixture-install").exists())
        self.assertEqual(run("git", "rev-parse", "HEAD", cwd=self.source), self.base)

    def test_pin_change_without_remote_name_invalidates_fixed_dependencies(self):
        new = self.advance_remote()
        self.pin = new
        self.configure()
        self.reset()
        self.assertEqual(run("git", "rev-parse", "HEAD", cwd=self.source), new)
        self.assert_invalidated()

    def test_git_tag_sha_works_on_detached_head(self):
        self.tag = self.base
        self.configure()
        self.reset()
        self.populate()
        run("git", "checkout", "-q", "--detach", self.base, cwd=self.source)
        self.assertEqual(self.reset(), "")

    def test_pin_missing_from_shallow_cache_is_fetched(self):
        self.advance_remote()
        shutil.rmtree(self.source)
        run("git", "clone", "-q", "--depth=1", self.remote.as_uri(),
            str(self.source))
        self.pin = self.base
        self.configure()
        self.reset()
        self.assertEqual(run("git", "rev-parse", "HEAD", cwd=self.source), self.base)
        self.assert_invalidated()

    def test_recipe_change_invalidates_completed_build(self):
        self.harness.write_text(self.harness.read_text() + "\n# changed recipe\n")
        run("cmake", "-S", str(self.root), "-B", str(self.build))
        self.assertIn("recipe or patches changed", self.reset())
        self.assert_invalidated()

    def test_patch_content_change_invalidates_completed_build(self):
        patch = self.root / "fixture-0001.patch"
        patch.write_text("initial patch\n")
        self.configure()
        self.reset()
        self.populate()
        patch.write_text("updated patch\n")
        self.configure()
        self.assertIn("recipe or patches changed", self.reset())
        self.assert_invalidated()

    def test_non_git_cleanup_does_not_call_git_reset_script(self):
        run("cmake", "--build", str(self.build), "--target", "archive")

    def test_completed_legacy_build_applies_changed_patch_after_ci_update(self):
        patch = self.root / "fixture-0001.patch"

        def write_patch(version):
            run("git", "reset", "--hard", "-q", self.base, cwd=self.seed)
            (self.seed / "source.txt").write_text(version + "\n")
            run("git", "commit", "-qam", version, cwd=self.seed)
            patch.write_text(run("git", "format-patch", "-1", "--stdout",
                                 cwd=self.seed) + "\n")

        write_patch("v1")
        installed = self.root / "installed-source.txt"
        project = self.harness.read_text().replace(
            'UPDATE_COMMAND "" CONFIGURE_COMMAND "" BUILD_COMMAND "" INSTALL_COMMAND "")',
            f'''PATCH_COMMAND git am --3way "{patch}"
 UPDATE_COMMAND "" CONFIGURE_COMMAND "" BUILD_COMMAND ""
 INSTALL_COMMAND "${{CMAKE_COMMAND}}" -E copy <SOURCE_DIR>/source.txt "{installed}")''', 1)
        project += "\nExternalProject_Add_StepTargets(fixture download)\n"
        self.harness.write_text(project)
        run("cmake", "-S", str(self.root), "-B", str(self.build))
        self.reset()
        run("cmake", "--build", str(self.build), "--target", "fixture")
        self.assertEqual(installed.read_text(), "v1\n")
        self.assertTrue((self.stamp / "fixture-postremovebuild").exists())

        # Legacy successes have completed stamps but no way to prove which
        # patch contents produced them. Replay the CI restore/update sequence
        # after changing a patch in place, without changing its command path.
        (self.stamp / "RECIPE").unlink()
        write_patch("v2")
        run("cmake", "--fresh", "-G", "Ninja", "-S", str(self.root),
            "-B", str(self.build))
        run("cmake", "--build", str(self.build), "--target", "fixture-download")
        run("cmake", "--build", str(self.build), "--target", "fixture-force-update")
        run("cmake", "--build", str(self.build), "--target", "fixture")
        self.assertEqual(installed.read_text(), "v2\n")
        self.assertEqual((self.source / "source.txt").read_text(), "v2\n")

        # The migration is one-time: a completed cache with the new recipe
        # fingerprint remains reusable without another install or source reset.
        installed_at = (self.stamp / "fixture-install").stat().st_mtime_ns
        self.assertEqual(self.reset(), "")
        run("cmake", "--build", str(self.build), "--target", "fixture")
        self.assertEqual((self.stamp / "fixture-install").stat().st_mtime_ns,
                         installed_at)

    def test_actual_build_recovers_reset_source_and_skipped_configure(self):
        # A real CMake library rejects source that has lost the configure-time
        # edit, just as libbluray's restored SSP probe rejects the CI sysroot.
        (self.seed / "CMakeLists.txt").write_text('''cmake_minimum_required(VERSION 3.19)
project(cache_fixture C)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/source.txt" prepared)
if(NOT prepared STREQUAL "prepared\\n")
 message(FATAL_ERROR "configure-time source preparation was lost")
endif()
add_library(cache_fixture STATIC fixture.c)
install(TARGETS cache_fixture ARCHIVE DESTINATION lib)
''')
        (self.seed / "fixture.c").write_text("int cache_fixture(void) { return 42; }\n")
        run("git", "add", ".", cwd=self.seed)
        run("git", "commit", "-qm", "build fixture", cwd=self.seed)
        run("git", "push", "-q", str(self.remote), "main", cwd=self.seed)
        run("git", "pull", "-q", cwd=self.source)
        self.base = run("git", "rev-parse", "HEAD", cwd=self.source)
        prepare = self.root / "prepare.cmake"
        prepare.write_text(f'file(WRITE "{self.source}/source.txt" "prepared\\n")\n')
        project = self.harness.read_text().replace(
            'UPDATE_COMMAND "" CONFIGURE_COMMAND "" BUILD_COMMAND "" INSTALL_COMMAND "")',
            f'''UPDATE_COMMAND ""
 CONFIGURE_COMMAND "${{CMAKE_COMMAND}}" -P "{prepare}"
 COMMAND "${{CMAKE_COMMAND}}" -S <SOURCE_DIR> -B <BINARY_DIR>
  -DCMAKE_INSTALL_PREFIX={self.root}/install
 BUILD_COMMAND "${{CMAKE_COMMAND}}" --build <BINARY_DIR>
 INSTALL_COMMAND "${{CMAKE_COMMAND}}" --install <BINARY_DIR>)''', 1)
        project += "\nExternalProject_Add_StepTargets(fixture build)\n"
        self.harness.write_text(project)
        run("cmake", "-S", str(self.root), "-B", str(self.build))
        self.reset()
        run("cmake", "--build", str(self.build), "--target", "fixture-build")
        # Simulate an old failed run: build is stamped complete, install is
        # pending, and force-update has already discarded the source edit.
        run("git", "reset", "--hard", "-q", cwd=self.source)
        (self.stamp / "RECIPE").unlink()
        self.reset()
        run("cmake", "--build", str(self.build), "--target", "fixture")
        self.assertTrue((self.root / "install/lib/libcache_fixture.a").is_file())
        self.assertTrue((self.stamp / "fixture-postremovebuild").exists())
        self.assertEqual((self.source / "source.txt").read_text(), "upstream\n")
        installed_at = (self.stamp / "fixture-install").stat().st_mtime_ns
        self.assertEqual(self.reset(), "")
        run("cmake", "--build", str(self.build), "--target", "fixture")
        self.assertEqual((self.stamp / "fixture-install").stat().st_mtime_ns,
                         installed_at)


if __name__ == "__main__":
    unittest.main(verbosity=2)
