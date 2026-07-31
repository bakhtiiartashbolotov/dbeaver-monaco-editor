#!/usr/bin/env python3
"""Verify that an extracted DBeaver tree exactly matches its verified archive."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tarfile
import tempfile

REGULAR_TYPES = (b"0", b"\0")
DIRECTORY_TYPE = b"5"


def fail(message: str) -> None:
    raise SystemExit(message)


def header_at(source: tarfile.TarFile, offset: int) -> bytes:
    position = source.fileobj.tell()
    source.fileobj.seek(offset)
    header = source.fileobj.read(tarfile.BLOCKSIZE)
    source.fileobj.seek(position)
    if len(header) != tarfile.BLOCKSIZE:
        fail("cannot read complete archive header")
    return header


def decode_header_name(header: bytes) -> str:
    name = header[:100].split(b"\0", 1)[0]
    prefix = header[345:500].split(b"\0", 1)[0]
    try:
        decoded = name.decode("utf-8")
        if prefix:
            decoded = f"{prefix.decode('utf-8')}/{decoded}"
    except UnicodeDecodeError:
        fail("non-UTF-8 archive path")
    return decoded


def raw_member(source: tarfile.TarFile, member: tarfile.TarInfo) -> tuple[str, bytes]:
    first = header_at(source, member.offset)
    first_type = first[156:157]
    if first_type == tarfile.GNUTYPE_LONGNAME:
        try:
            size = int(first[124:136].rstrip(b"\0 ") or b"0", 8)
        except ValueError:
            fail(f"invalid GNU long-name header: {member.name}")
        position = source.fileobj.tell()
        source.fileobj.seek(member.offset + tarfile.BLOCKSIZE)
        encoded = source.fileobj.read(size)
        source.fileobj.seek(position)
        if len(encoded) != size or not encoded.endswith(b"\0"):
            fail(f"malformed GNU long-name data: {member.name}")
        try:
            raw_name = encoded[:-1].decode("utf-8")
        except UnicodeDecodeError:
            fail(f"non-UTF-8 GNU long name: {member.name}")
        actual = header_at(source, member.offset_data - tarfile.BLOCKSIZE)
        return raw_name, actual[156:157]
    if first_type in (tarfile.XHDTYPE, tarfile.XGLTYPE, tarfile.GNUTYPE_LONGLINK):
        fail(f"unsupported archive extension header: {member.name}")
    return decode_header_name(first), first_type


def validated_members(
        source: tarfile.TarFile,
) -> tuple[dict[str, tuple[str, tarfile.TarInfo]], dict[str, tuple[str, int, str | None]]]:
    records: dict[str, tuple[str, tarfile.TarInfo]] = {}
    expected: dict[str, tuple[str, int, str | None]] = {}
    for member in source:
        raw, typeflag = raw_member(source, member)
        if typeflag == DIRECTORY_TYPE:
            kind = "directory"
        elif typeflag in REGULAR_TYPES:
            kind = "file"
        else:
            fail(f"unsupported archive entry type {typeflag!r}: {member.name}")

        if kind == "file" and raw.endswith("/"):
            fail(f"regular file archive path ends in slash: {raw}")
        if (not raw or raw.startswith("/") or raw.startswith("./") or "//" in raw or "\\" in raw
                or any(part in ("", ".", "..") for part in raw.rstrip("/").split("/"))):
            fail(f"unsafe archive path: {raw}")
        canonical = raw[:-1] if kind == "directory" and raw.endswith("/") else raw
        expected_spelling = f"{canonical}/" if kind == "directory" else canonical
        if raw != expected_spelling or member.name != canonical:
            fail(f"noncanonical archive path spelling: {raw}")
        if not canonical.startswith("dbeaver") or canonical.split("/", 1)[0] != "dbeaver":
            fail(f"unexpected archive top-level path: {raw}")
        if canonical in records:
            fail(f"duplicate or conflicting archive path: {canonical}")
        records[canonical] = (kind, member)

        if canonical == "dbeaver":
            if kind != "directory":
                fail("top-level dbeaver entry is not a directory")
            continue
        relative = canonical.removeprefix("dbeaver/")
        if kind == "directory":
            expected[relative] = (kind, 0, None)
        else:
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
            expected[relative] = (kind, size, digest.hexdigest())

    root = records.get("dbeaver")
    if root is None or root[0] != "directory":
        fail("archive must contain exactly one explicit canonical dbeaver/ directory")
    if not expected:
        fail("archive contains no DBeaver entries")
    for canonical in records:
        if canonical == "dbeaver":
            continue
        parent = canonical.rsplit("/", 1)[0]
        parent_record = records.get(parent)
        if parent_record is None:
            fail(f"archive path has no explicit parent directory: {canonical}")
        if parent_record[0] != "directory":
            fail(f"archive file is an ancestor of another member: {parent}")
    return records, expected


def verified_snapshot(archive: Path, expected_digest: str):
    if len(expected_digest) != 64 or any(character not in "0123456789abcdef" for character in expected_digest):
        fail("expected SHA-256 must be exactly 64 lowercase hexadecimal characters")
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(archive, flags)
    except OSError as error:
        fail(f"cannot securely open archive: {error}")
    with os.fdopen(descriptor, "rb") as source, tempfile.TemporaryFile() as snapshot:
        status = os.fstat(source.fileno())
        if not stat.S_ISREG(status.st_mode):
            fail("archive source is not a regular file")
        digest = hashlib.sha256()
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
            snapshot.write(chunk)
        if digest.hexdigest() != expected_digest:
            fail(f"archive SHA-256 mismatch: expected {expected_digest}, got {digest.hexdigest()}")
        snapshot.flush()
        snapshot.seek(0)
        yield snapshot


def extract_members(
        source: tarfile.TarFile,
        records: dict[str, tuple[str, tarfile.TarInfo]],
        install: Path,
) -> None:
    if install.exists() or install.is_symlink():
        fail(f"extraction destination already exists: {install}")
    directories = sorted(
        ((name, member) for name, (kind, member) in records.items()
         if kind == "directory" and name != "dbeaver"),
        key=lambda item: (item[0].count("/"), item[0]),
    )
    files = sorted((name, member) for name, (kind, member) in records.items() if kind == "file")
    install.mkdir(parents=True)
    for name, _ in directories:
        (install / name.removeprefix("dbeaver/")).mkdir()
    for name, member in files:
        destination = install / name.removeprefix("dbeaver/")
        stream = source.extractfile(member)
        if stream is None:
            fail(f"cannot extract archive file: {member.name}")
        with destination.open("xb") as target:
            shutil.copyfileobj(stream, target, 1024 * 1024)
        os.chmod(destination, member.mode & 0o777)
    for name, member in reversed(directories):
        os.chmod(install / name.removeprefix("dbeaver/"), member.mode & 0o777)


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
    archive = Path(sys.argv[2] if extract else sys.argv[1])
    install = Path(sys.argv[3] if extract else sys.argv[2])
    expected_digest = sys.argv[4] if extract else sys.argv[3]
    for snapshot in verified_snapshot(archive, expected_digest):
        with tarfile.open(fileobj=snapshot, mode="r:gz") as source:
            records, expected = validated_members(source)
            if extract:
                extract_members(source, records, install)
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
