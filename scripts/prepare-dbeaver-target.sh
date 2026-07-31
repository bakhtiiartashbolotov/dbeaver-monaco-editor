#!/usr/bin/env bash
set -euo pipefail

readonly version=26.1.0
readonly archive_name=dbeaver-ce-${version}-linux-x86_64.tar.gz
readonly archive_url=https://dbeaver.io/files/${version}/${archive_name}
readonly digest_file=releng/baseline/${archive_name}.sha256
readonly cache_dir=.cache/downloads
readonly archive=${cache_dir}/${archive_name}
readonly install_root=.cache/dbeaver-${version}
readonly install=${install_root}/dbeaver

[[ $# -eq 0 ]] || { echo 'prepare-dbeaver-target.sh accepts no arguments' >&2; exit 2; }
[[ -f "$digest_file" ]] || { echo "missing committed digest: $digest_file" >&2; exit 1; }
digest=$(tr -d '\r\n' < "$digest_file")
[[ "$digest" =~ ^[0-9a-f]{64}$ ]] || { echo 'invalid committed SHA-256 digest' >&2; exit 1; }
command -v curl >/dev/null || { echo 'curl is required' >&2; exit 1; }
if command -v sha256sum >/dev/null; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null; then
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  echo 'sha256sum or shasum is required' >&2; exit 1
fi
mkdir -p "$cache_dir"
if [[ -f "$archive" ]] && [[ "$(sha256 "$archive")" == "$digest" ]]; then
  echo "reusing verified archive: $archive"
else
  rm -f "$archive" "$archive.tmp" "$archive.headers"
  curl --proto '=https' --proto-redir '=https' -fsSIL -D "$archive.headers" -o /dev/null "$archive_url"
  python3 - "$archive.headers" <<'PY'
import sys
from urllib.parse import urlparse
allowed = {'dbeaver.io', 'github.com', 'release-assets.githubusercontent.com'}
for line in open(sys.argv[1], encoding='iso-8859-1'):
    if line.lower().startswith('location:'):
        host = urlparse(line.split(':', 1)[1].strip()).hostname
        if host not in allowed:
            raise SystemExit(f'unallowlisted redirect host: {host}')
PY
  curl --proto '=https' --proto-redir '=https' -fsSL "$archive_url" -o "$archive.tmp"
  actual=$(sha256 "$archive.tmp")
  [[ "$actual" == "$digest" ]] || { echo "SHA-256 mismatch: expected $digest, got $actual" >&2; rm -f "$archive.tmp"; exit 1; }
  mv "$archive.tmp" "$archive"
fi
[[ "$(sha256 "$archive")" == "$digest" ]] || { echo 'cached archive failed verification' >&2; exit 1; }
if [[ -d "$install" ]]; then
  echo "reusing prepared installation: $install"
  exit 0
fi
rm -rf "${install_root}.tmp"
mkdir -p "${install_root}.tmp"
tar -xzf "$archive" -C "${install_root}.tmp"
[[ -d "${install_root}.tmp/dbeaver" ]] || { echo 'archive did not contain dbeaver/' >&2; rm -rf "${install_root}.tmp"; exit 1; }
mv "${install_root}.tmp" "$install_root"
echo "prepared DBeaver target: $install"
