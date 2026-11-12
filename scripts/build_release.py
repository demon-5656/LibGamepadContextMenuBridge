#!/usr/bin/env python3
"""Build only the installable addon files; never execute or install the addon."""
import os
from pathlib import Path
import re
import sys
import tempfile
import zipfile


ADDON = "LibGamepadContextMenuBridge"
FILES = (f"{ADDON}.txt", f"{ADDON}.lua", "README.md", "CREDITS.md")


def single_match(pattern, text, label):
    matches = re.findall(pattern, text, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one {label}")
    return matches[0]


def build(root):
    addon = root / ADDON
    if addon.is_symlink() or not addon.is_dir():
        raise ValueError("Addon directory must be a real directory")
    sources = [(name, addon / name) for name in FILES] + [("LICENSE", root / "LICENSE")]
    for _, source in sources:
        if source.is_symlink() or not source.is_file():
            raise ValueError(f"Missing or symlinked release file: {source}")
    # Snapshot the exact bytes validated below and written to the archive.
    contents = {name: source.read_bytes() for name, source in sources}
    manifest = contents[f"{ADDON}.txt"].decode("utf-8-sig")
    lua = contents[f"{ADDON}.lua"].decode("utf-8-sig")
    runtime_files = [line.strip() for line in manifest.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    if runtime_files != [f"{ADDON}.lua"]:
        raise ValueError("Manifest runtime files differ from the release allowlist")
    version = single_match(r"^## Version:[ \t]*([^\r\n]+)", manifest, "manifest Version").strip()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Version must contain three numeric components")
    minor = single_match(r"^## AddOnVersion:[ \t]*([^\r\n]+)", manifest, "manifest AddOnVersion").strip()
    if not re.fullmatch(r"[1-9][0-9]*", minor):
        raise ValueError("AddOnVersion must be a positive integer")
    lua_version = single_match(r'^local ADDON_VERSION\s*=\s*"([^"\r\n]+)"[ \t]*\r?$', lua, "Lua ADDON_VERSION")
    lua_minor = single_match(r"^local MINOR\s*=\s*([0-9]+)[ \t]*\r?$", lua, "Lua MINOR")
    if lua_version != version or lua_minor != minor:
        raise ValueError("Manifest and Lua versions do not match")
    dist = root / "dist"
    if dist.is_symlink():
        raise ValueError("Output directory must not be a symlink")
    dist.mkdir(exist_ok=True)
    if not dist.is_dir():
        raise ValueError("Output path must be a directory")
    archive = dist / f"{ADDON}-v{version}.zip"
    if os.path.lexists(archive):
        raise FileExistsError(f"Refusing to overwrite: {archive}")
    with tempfile.TemporaryDirectory(prefix=".lgcmb-build.", dir=dist) as staging:
        temporary_zip = Path(staging) / "release.zip"
        with zipfile.ZipFile(temporary_zip, "x", compression=zipfile.ZIP_DEFLATED) as package:
            for name, content in contents.items():
                package.writestr(f"{ADDON}/{name}", content)
        with zipfile.ZipFile(temporary_zip) as package:
            expected = {f"{ADDON}/{name}" for name in contents}
            if set(package.namelist()) != expected or package.testzip() is not None:
                raise ValueError("Archive content or CRC verification failed")
            for name, content in contents.items():
                if package.read(f"{ADDON}/{name}") != content:
                    raise ValueError(f"Archive byte verification failed: {name}")
        # Same-filesystem publication is atomic and cannot replace an existing file.
        os.link(temporary_zip, archive)
    return archive


if __name__ == "__main__":
    try:
        print(f"Built: {build(Path(__file__).resolve().parent.parent)}")
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"Packaging failed: {error}", file=sys.stderr)
        sys.exit(1)
