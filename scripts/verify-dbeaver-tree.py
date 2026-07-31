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


def validated_members(archive: Path) -> tuple[list[tarfile.TarInfo], dict[str, tuple[str, int, str | None]]]:
    members: list[tarfile.TarInfo] = []
    expected: dict[str, tuple[str, int, str | None]] = {}
    seen: set[str] = set()
    root_count = 0
    with tarfile.open(archive, "r:gz") as source:
        for member in source:
            raw = member.name
            path = PurePosixPath(member.name)
            canonical = path.as_posix()
            if (path.is_absolute() or not path.parts or any(part in ("", ".", "..") for part in path.parts)
                    or "//" in raw or raw.startswith("./") or "\\" in raw
                    or raw.rstrip("/") != canonical):
                fail(f"unsafe archive path: {member.name}")
            if path.parts[0] != "dbeaver":
                fail(f"unexpected archive top-level path: {member.name}")
            normalized = canonical.rstrip("/")
            if normalized in seen:
                fail(f"duplicate archive path: {normalized}")
            seen.add(normalized)
            members.append(member)
            if len(path.parts) == 1:
                relative = ""
            else:
                relative = PurePosixPath(*path.parts[1:]).as_posix()
            if not relative:
                if not member.isdir():
                    fail("top-level dbeaver entry is not a directory")
                root_count += 1
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
    if root_count != 1:
        fail(f"archive must contain exactly one explicit dbeaver directory entry; found {root_count}")
    if not expected:
        fail("archive contains no DBeaver entries")
    return members, expected


def archive_manifest(archive: Path) -> dict[str, tuple[str, int, str | None]]:
    return validated_members(archive)[1]


def extract_verified_archive(archive: Path, install: Path) -> None:
    members, _ = validated_members(archive)
    if install.exists() or install.is_symlink():
        fail(f"extraction destination already exists: {install}")
    install.mkdir(parents=True)
    with tarfile.open(archive, "r:gz") as source:
        by_name = {member.name.rstrip("/"): member for member in source}
        for original in members:
            if len(PurePosixPath(original.name).parts) == 1:
                continue
            member = by_name[original.name.rstrip("/")]
            relative = Path(*PurePosixPath(member.name).parts[1:])
            destination = install / relative
            if member.isdir():
                destination.mkdir()
                os.chmod(destination, member.mode & 0o777)
            else:
                stream = source.extractfile(member)
                if stream is None:
                    fail(f"cannot extract archive file: {member.name}")
                destination.parent.mkdir(parents=True, exist_ok=True)
                with destination.open("xb") as target:
                    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                        target.write(chunk)
                os.chmod(destination, member.mode & 0o777)


def installed_manifest(install: Path) -> dict[str, tuple[str, int, str | None]]:
    actual: dict[str, tuple[str, int, str | None]] = {}
    inodes: set[tuple[int, int]] = set()
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
                if status.st_nlink != 1:
                    fail(f"installed hardlink is forbidden: {relative} has {status.st_nlink} links")
                inode = (status.st_dev, status.st_ino)
                if inode in inodes:
                    fail(f"installed inode reuse is forbidden: {relative}")
                inodes.add(inode)
                digest = hashlib.sha256()
                with path.open("rb") as source:
                    for chunk in iter(lambda: source.read(1024 * 1024), b""):
                        digest.update(chunk)
                actual[relative] = ("file", status.st_size, digest.hexdigest())
            else:
                fail(f"installed special file is forbidden: {relative}")
    return actual


def main() -> None:
    extract = len(sys.argv) == 4 and sys.argv[1] == "--extract"
    if (extract and len(sys.argv) != 4) or (not extract and len(sys.argv) != 3):
        fail(f"usage: {sys.argv[0]} [--extract] <verified-archive> <installation>")
    archive = Path(sys.argv[2] if extract else sys.argv[1]).resolve(strict=True)
    install = Path(sys.argv[3] if extract else sys.argv[2])
    if extract:
        extract_verified_archive(archive, install)
        actual = installed_manifest(install)
        expected = archive_manifest(archive)
        if expected != actual:
            fail("extracted installation does not match archive")
        print(f"extracted exact DBeaver installation tree: {len(actual)} entries")
        return
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
