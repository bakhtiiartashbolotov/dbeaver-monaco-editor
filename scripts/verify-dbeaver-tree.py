#!/usr/bin/env python3
"""Verify that an extracted DBeaver tree exactly matches its verified archive."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path, PurePosixPath
import stat
import sys
import tarfile


def fail(message: str) -> None:
    raise SystemExit(message)


def archive_manifest(archive: Path) -> dict[str, tuple[str, int, str | None]]:
    expected: dict[str, tuple[str, int, str | None]] = {}
    with tarfile.open(archive, "r:gz") as source:
        for member in source:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or not path.parts:
                fail(f"unsafe archive path: {member.name}")
            if path.parts[0] != "dbeaver":
                fail(f"unexpected archive top-level path: {member.name}")
            normalized = path.as_posix().rstrip("/")
            if normalized in expected:
                fail(f"duplicate archive path: {normalized}")
            if len(path.parts) == 1:
                relative = ""
            else:
                relative = PurePosixPath(*path.parts[1:]).as_posix()
            if not relative:
                if not member.isdir():
                    fail("top-level dbeaver entry is not a directory")
                continue
            if member.isdir():
                expected[relative] = ("directory", 0, None)
            elif member.isfile():
                extracted = source.extractfile(member)
                if extracted is None:
                    fail(f"cannot read archive file: {member.name}")
                digest = hashlib.sha256()
                size = 0
                for chunk in iter(lambda: extracted.read(1024 * 1024), b""):
                    digest.update(chunk)
                    size += len(chunk)
                if size != member.size:
                    fail(f"archive size mismatch: {member.name}")
                expected[relative] = ("file", size, digest.hexdigest())
            else:
                fail(f"unsupported archive entry type: {member.name}")
    if not expected:
        fail("archive contains no DBeaver entries")
    return expected


def installed_manifest(install: Path) -> dict[str, tuple[str, int, str | None]]:
    actual: dict[str, tuple[str, int, str | None]] = {}
    root_status = install.lstat()
    if not stat.S_ISDIR(root_status.st_mode) or stat.S_ISLNK(root_status.st_mode):
        fail(f"installation root is not a real directory: {install}")
    for current, directories, files in os.walk(install, topdown=True, followlinks=False):
        current_path = Path(current)
        for name in sorted(directories + files):
            path = current_path / name
            relative = path.relative_to(install).as_posix()
            status = path.lstat()
            if stat.S_ISLNK(status.st_mode):
                fail(f"installed symlink is forbidden: {relative}")
            if stat.S_ISDIR(status.st_mode):
                actual[relative] = ("directory", 0, None)
            elif stat.S_ISREG(status.st_mode):
                digest = hashlib.sha256()
                with path.open("rb") as source:
                    for chunk in iter(lambda: source.read(1024 * 1024), b""):
                        digest.update(chunk)
                actual[relative] = ("file", status.st_size, digest.hexdigest())
            else:
                fail(f"installed special file is forbidden: {relative}")
    return actual


def main() -> None:
    if len(sys.argv) != 3:
        fail(f"usage: {sys.argv[0]} <verified-archive> <installation>")
    archive = Path(sys.argv[1]).resolve(strict=True)
    install = Path(sys.argv[2])
    if not install.exists():
        fail(f"installation is missing: {install}")
    expected = archive_manifest(archive)
    actual = installed_manifest(install)
    if expected != actual:
        missing = sorted(expected.keys() - actual.keys())
        extra = sorted(actual.keys() - expected.keys())
        changed = sorted(path for path in expected.keys() & actual.keys() if expected[path] != actual[path])
        fail(f"installation tree mismatch; missing={missing[:3]}, extra={extra[:3]}, changed={changed[:3]}")
    print(f"verified exact DBeaver installation tree: {len(actual)} entries")


if __name__ == "__main__":
    main()
