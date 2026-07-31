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


def raw_header_name(source: tarfile.TarFile, member: tarfile.TarInfo) -> str:
    position = source.fileobj.tell()
    source.fileobj.seek(member.offset)
    header = source.fileobj.read(tarfile.BLOCKSIZE)
    if len(header) != tarfile.BLOCKSIZE:
        fail(f"cannot read archive header: {member.name}")
    if header[156:157] == tarfile.GNUTYPE_LONGNAME:
        try:
            size = int(header[124:136].rstrip(b"\0 ") or b"0", 8)
        except ValueError:
            fail(f"invalid GNU long-name header: {member.name}")
        name = source.fileobj.read(size).split(b"\0", 1)[0]
        prefix = b""
    else:
        name = header[:100].split(b"\0", 1)[0]
        prefix = header[345:500].split(b"\0", 1)[0]
    source.fileobj.seek(position)
    try:
        decoded = name.decode("utf-8")
        if prefix:
            decoded = f"{prefix.decode('utf-8')}/{decoded}"
    except UnicodeDecodeError:
        fail(f"non-UTF-8 archive path: {member.name}")
    return decoded


def validated_members(source: tarfile.TarFile) -> tuple[list[tarfile.TarInfo], dict[str, tuple[str, int, str | None]]]:
    members: list[tarfile.TarInfo] = []
    expected: dict[str, tuple[str, int, str | None]] = {}
    seen: set[str] = set()
    root_count = 0
    for member in source:
        raw = raw_header_name(source, member)
        path = PurePosixPath(member.name)
        canonical = path.as_posix()
        expected_spelling = f"{canonical}/" if member.isdir() else canonical
        if (raw != expected_spelling or path.is_absolute() or not path.parts
                or any(part in ("", ".", "..") for part in path.parts)
                or "//" in raw or raw.startswith("./") or "\\" in raw
                or member.name != canonical):
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


def verify_digest(stream, expected_digest: str) -> None:
    if len(expected_digest) != 64 or any(character not in "0123456789abcdef" for character in expected_digest):
        fail("expected SHA-256 must be exactly 64 lowercase hexadecimal characters")
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(chunk)
    if digest.hexdigest() != expected_digest:
        fail(f"archive SHA-256 mismatch: expected {expected_digest}, got {digest.hexdigest()}")
    stream.seek(0)


def extract_members(source: tarfile.TarFile, members: list[tarfile.TarInfo], install: Path) -> None:
    if install.exists() or install.is_symlink():
        fail(f"extraction destination already exists: {install}")
    install.mkdir(parents=True)
    for member in members:
        if len(PurePosixPath(member.name).parts) == 1:
            continue
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
    extract = len(sys.argv) == 5 and sys.argv[1] == "--extract"
    if (extract and len(sys.argv) != 5) or (not extract and len(sys.argv) != 4):
        fail(f"usage: {sys.argv[0]} [--extract] <archive> <installation> <expected-sha256>")
    archive = Path(sys.argv[2] if extract else sys.argv[1]).resolve(strict=True)
    install = Path(sys.argv[3] if extract else sys.argv[2])
    expected_digest = sys.argv[4] if extract else sys.argv[3]
    with archive.open("rb") as archive_bytes:
        verify_digest(archive_bytes, expected_digest)
        with tarfile.open(fileobj=archive_bytes, mode="r:gz") as source:
            members, expected = validated_members(source)
            if extract:
                extract_members(source, members, install)
    if not install.exists():
        fail(f"installation is missing: {install}")
    actual = installed_manifest(install)
    if expected != actual:
        missing = sorted(expected.keys() - actual.keys())
        extra = sorted(actual.keys() - expected.keys())
        changed = sorted(path for path in expected.keys() & actual.keys() if expected[path] != actual[path])
        fail(f"installation tree mismatch; missing={missing[:3]}, extra={extra[:3]}, changed={changed[:3]}")
    action = "extracted" if extract else "verified"
    print(f"{action} exact DBeaver installation tree: {len(actual)} entries")


if __name__ == "__main__":
    main()
