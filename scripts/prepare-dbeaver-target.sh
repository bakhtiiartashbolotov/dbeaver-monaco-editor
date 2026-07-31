#!/usr/bin/env bash
set -euo pipefail

readonly version=26.1.0
readonly archive_name=dbeaver-ce-${version}-linux-x86_64.tar.gz
readonly archive_url=https://dbeaver.io/files/${version}/${archive_name}
readonly digest_file=releng/baseline/${archive_name}.sha256
readonly repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
readonly cache_root=${repo_root}/.cache
readonly cache_dir=${cache_root}/downloads
readonly archive=${cache_dir}/${archive_name}
readonly install_root=${cache_root}/dbeaver-${version}
readonly install=${install_root}/dbeaver
readonly max_redirects=5
readonly allowed_hosts='dbeaver.io github.com release-assets.githubusercontent.com'

temporary_download=''
staging_root=''
backup_root=''
lock_root=''
cleanup() {
  status=$?
  if [[ -n "$backup_root" && -e "$backup_root" ]]; then
    rm -rf "$install_root"
    mv "$backup_root" "$install_root"
  fi
  [[ -z "$temporary_download" ]] || rm -rf "$temporary_download"
  [[ -z "$staging_root" ]] || rm -rf "$staging_root"
  [[ -z "$lock_root" ]] || rmdir "$lock_root" 2>/dev/null || true
  return "$status"
}
trap cleanup EXIT

[[ $# -eq 0 ]] || { echo 'prepare-dbeaver-target.sh accepts no arguments' >&2; exit 2; }
[[ -f "$repo_root/$digest_file" ]] || { echo "missing committed digest: $digest_file" >&2; exit 1; }
mapfile -t digest_lines < "$repo_root/$digest_file"
[[ ${#digest_lines[@]} -eq 1 ]] || { echo 'digest file must contain exactly one line' >&2; exit 1; }
digest=${digest_lines[0]}
[[ "$digest" =~ ^[0-9a-f]{64}$ ]] || { echo 'invalid committed SHA-256 digest' >&2; exit 1; }
command -v curl >/dev/null || { echo 'curl is required' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'python3 is required' >&2; exit 1; }

if command -v sha256sum >/dev/null; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null; then
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  echo 'sha256sum or shasum is required' >&2
  exit 1
fi

validate_url() {
  python3 - "$1" "$allowed_hosts" <<'PY'
import sys
from urllib.parse import urlsplit
url = urlsplit(sys.argv[1])
allowed = set(sys.argv[2].split())
if (url.scheme != "https" or url.hostname not in allowed or url.username or url.password
        or url.port is not None or url.fragment):
    raise SystemExit(f"rejected redirect URL: {sys.argv[1]}")
print(url.hostname)
PY
}

resolve_location() {
  python3 - "$1" "$2" <<'PY'
import sys
from urllib.parse import urljoin
print(urljoin(sys.argv[1], sys.argv[2]))
PY
}

download_with_validated_redirects() {
  local current_url=$1
  local output=$2
  local redirect_count=0
  local response_dir=$temporary_download/response
  mkdir -p "$response_dir"
  : > "$temporary_download/redirect-chain.txt"

  while true; do
    local host status location
    host=$(validate_url "$current_url")
    printf 'GET %s %s\n' "$host" "$current_url" >> "$temporary_download/redirect-chain.txt"
    rm -f "$response_dir/headers" "$response_dir/body"
    status=$(curl --proto '=https' --max-redirs 0 --silent --show-error \
      --dump-header "$response_dir/headers" --output "$response_dir/body" \
      --write-out '%{http_code}' "$current_url")
    case "$status" in
      200|201|202|203|204|205|206)
        mv "$response_dir/body" "$output"
        cat "$temporary_download/redirect-chain.txt"
        return 0
        ;;
      301|302|303|307|308)
        (( redirect_count < max_redirects )) || { echo 'redirect limit exceeded' >&2; return 1; }
        location=$(python3 - "$response_dir/headers" <<'PYLOCATION'
import sys
values = []
for line in open(sys.argv[1], encoding="iso-8859-1"):
    if line.lower().startswith("location:"):
        values.append(line.split(":", 1)[1].strip())
if len(values) == 1:
    print(values[0])
PYLOCATION
)
        [[ -n "$location" && $(printf '%s\n' "$location" | wc -l) -eq 1 ]] || {
          echo 'missing or ambiguous redirect Location' >&2
          return 1
        }
        current_url=$(resolve_location "$current_url" "$location")
        validate_url "$current_url" >/dev/null
        ((redirect_count += 1))
        ;;
      *)
        echo "download failed with HTTP $status" >&2
        return 1
        ;;
    esac
  done
}

cd "$repo_root"
if [[ -L "$cache_root" ]]; then
  echo "cache root must not be a symlink: $cache_root" >&2
  exit 1
fi
mkdir -p "$cache_root"
[[ "$(realpath -P "$cache_root")" == "$cache_root" ]] || { echo 'cache root escaped workspace' >&2; exit 1; }
if [[ -L "$cache_dir" || -L "$install_root" || -L "$archive" ]]; then
  echo 'cache download, archive, or installation path must not be a symlink' >&2
  exit 1
fi
mkdir -p "$cache_dir"
[[ "$(realpath -P "$cache_dir")" == "$cache_dir" ]] || { echo 'download cache escaped workspace' >&2; exit 1; }
lock_root=$cache_root/.prepare-dbeaver-${version}.lock
mkdir "$lock_root" || { echo 'another DBeaver preparation is active' >&2; exit 1; }
if [[ -f "$archive" && "$(sha256 "$archive")" == "$digest" ]]; then
  echo "reusing verified archive: $archive"
else
  rm -f "$archive"
  temporary_download=$(mktemp -d "$cache_dir/.${archive_name}.download.XXXXXX")
  download_with_validated_redirects "$archive_url" "$temporary_download/$archive_name"
  actual=$(sha256 "$temporary_download/$archive_name")
  [[ "$actual" == "$digest" ]] || {
    echo "SHA-256 mismatch: expected $digest, got $actual" >&2
    exit 1
  }
  mv "$temporary_download/$archive_name" "$archive"
  rm -rf "$temporary_download"
  temporary_download=''
fi
[[ "$(sha256 "$archive")" == "$digest" ]] || { echo 'cached archive failed verification' >&2; exit 1; }

if [[ -d "$install" ]] && python3 scripts/verify-dbeaver-tree.py "$archive" "$install"; then
  echo "reusing exact verified installation: $install"
  exit 0
fi

staging_root=$(mktemp -d "$cache_root/.dbeaver-${version}.staging.XXXXXX")
python3 scripts/verify-dbeaver-tree.py --extract "$archive" "$staging_root/dbeaver"
[[ -d "$staging_root/dbeaver/plugins" ]] || {
  echo 'archive did not contain a complete dbeaver installation' >&2
  exit 1
}
python3 scripts/verify-dbeaver-tree.py "$archive" "$staging_root/dbeaver"
if [[ -e "$install_root" ]]; then
  echo "replacing incomplete or unverified installation: $install_root"
  backup_root=$(mktemp -d "$cache_root/.dbeaver-${version}.previous.XXXXXX")
  rmdir "$backup_root"
  mv "$install_root" "$backup_root"
fi
if [[ ${DBEAVER_PREPARE_TEST_FAIL_PUBLISH:-0} == 1 ]]; then
  echo 'simulated publication failure' >&2
  exit 1
fi
mv "$staging_root" "$install_root"
staging_root=''
[[ -z "$backup_root" ]] || rm -rf "$backup_root"
backup_root=''
echo "prepared DBeaver target: $install"
