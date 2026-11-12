"""Exercise release packaging in disposable fixture repositories, never the game.

Run from the repository root: python3 -B scripts/tests/test_packaging.py
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / "build_release.sh"
ADDON = "LibGamepadContextMenuBridge"
EXPECTED = {
    f"{ADDON}/{ADDON}.lua",
    f"{ADDON}/{ADDON}.txt",
    f"{ADDON}/README.md",
    f"{ADDON}/CREDITS.md",
    f"{ADDON}/LICENSE",
}


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="lgcmb-package-", dir=os.environ.get("TMPDIR"))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        shutil.copy2(SCRIPT, self.root / "scripts/build_release.sh")
        helper = SCRIPT.with_suffix(".py")
        if helper.exists():
            shutil.copy2(helper, self.root / "scripts/build_release.py")
        self.addon = self.root / ADDON
        self.addon.mkdir()
        (self.addon / f"{ADDON}.txt").write_text(
            "## Version: 1.5.5\n## AddOnVersion: 155\n" + f"{ADDON}.lua\n", encoding="utf-8"
        )
        (self.addon / f"{ADDON}.lua").write_text(
            'local MINOR = 155\nlocal ADDON_VERSION = "1.5.5"\n', encoding="utf-8"
        )
        (self.addon / "README.md").write_text("Player instructions\n", encoding="utf-8")
        (self.addon / "CREDITS.md").write_text("Credits\n", encoding="utf-8")
        (self.root / "LICENSE").write_text("Synthetic license fixture\n", encoding="utf-8")
        self.archive = self.root / "dist" / f"{ADDON}-v1.5.5.zip"

    def run_build(self, **env):
        return subprocess.run(
            ["/bin/bash", str(self.root / "scripts/build_release.sh")],
            cwd=self.root, env={**os.environ, **env}, capture_output=True, text=True,
        )

    def assert_rejected(self):
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.archive.exists())

    def test_exact_zip_allowlist_and_bytes(self):
        (self.addon / "private-backup.lua").write_text("must not ship", encoding="utf-8")
        (self.addon / ".secret").write_text("must not ship", encoding="utf-8")
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.archive) as archive:
            self.assertEqual(set(archive.namelist()), EXPECTED)
            self.assertIsNone(archive.testzip())
            for name in EXPECTED:
                relative = Path(name).relative_to(ADDON)
                source = self.root / "LICENSE" if relative.name == "LICENSE" else self.addon / relative
                self.assertEqual(archive.read(name), source.read_bytes())
        self.assertFalse(list((self.root / "dist").glob(".lgcmb-build.*")))

    def test_existing_archive_is_preserved(self):
        self.archive.parent.mkdir()
        self.archive.write_bytes(b"previous release")
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.archive.read_bytes(), b"previous release")

    def test_missing_license_is_rejected(self):
        (self.root / "LICENSE").unlink()
        self.assert_rejected()

    def test_missing_allowlisted_file_is_rejected(self):
        (self.addon / "CREDITS.md").unlink()
        self.assert_rejected()

    def test_symlink_is_rejected(self):
        target = self.root / "outside.lua"
        target.write_text('local MINOR = 155\nlocal ADDON_VERSION = "1.5.5"\n', encoding="utf-8")
        source = self.addon / f"{ADDON}.lua"
        source.unlink()
        source.symlink_to(target)
        self.assert_rejected()

    def test_invalid_version_is_rejected(self):
        manifest = self.addon / f"{ADDON}.txt"
        manifest.write_text(manifest.read_text().replace("1.5.5", "../escape"), encoding="utf-8")
        self.assert_rejected()

    def test_duplicate_version_is_rejected(self):
        manifest = self.addon / f"{ADDON}.txt"
        manifest.write_text(manifest.read_text() + "## Version: 1.5.5\n", encoding="utf-8")
        self.assert_rejected()

    def test_lua_version_mismatch_is_rejected(self):
        source = self.addon / f"{ADDON}.lua"
        source.write_text(source.read_text().replace('"1.5.5"', '"1.5.4"'), encoding="utf-8")
        self.assert_rejected()

    def test_numeric_version_mismatch_is_rejected(self):
        source = self.addon / f"{ADDON}.lua"
        source.write_text(source.read_text().replace("155", "154"), encoding="utf-8")
        self.assert_rejected()

    def test_unlisted_manifest_code_is_rejected(self):
        manifest = self.addon / f"{ADDON}.txt"
        manifest.write_text(manifest.read_text() + "extra.lua\n", encoding="utf-8")
        (self.addon / "extra.lua").write_text("-- required module\n", encoding="utf-8")
        self.assert_rejected()

    def test_standard_library_build_needs_no_zip_executable(self):
        tools = self.root / "tools"
        tools.mkdir()
        for name in ("dirname", "python3"):
            command = shutil.which(name)
            assert command is not None, f"Test prerequisite missing: {name}"
            (tools / name).symlink_to(command)
        result = self.run_build(PATH=str(tools))
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.archive) as archive:
            self.assertEqual(set(archive.namelist()), EXPECTED)

    def test_concurrent_build_cannot_overwrite(self):
        argv = ["/bin/bash", str(self.root / "scripts/build_release.sh")]
        children = [subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
        results = [(child.communicate(), child.returncode) for child in children]
        self.assertEqual(sorted(code for _, code in results), [0, 1], results)
        with zipfile.ZipFile(self.archive) as archive:
            self.assertEqual(set(archive.namelist()), EXPECTED)
            self.assertIsNone(archive.testzip())

    def test_symlinked_dist_is_rejected_without_external_write(self):
        external = self.root / "external-output"
        external.mkdir()
        (self.root / "dist").symlink_to(external, target_is_directory=True)
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(list(external.iterdir()), [])

    def test_missing_python_does_not_create_tarball(self):
        tools = self.root / "tools"
        tools.mkdir()
        for name in ("dirname", "awk", "tr", "mkdir", "rm", "tar"):
            command = shutil.which(name)
            if command:
                (tools / name).symlink_to(command)
        result = self.run_build(PATH=str(tools))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(list(self.root.rglob("*.tar.gz")))
        self.assertFalse(self.archive.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
