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
readonly install_marker=${install_root}/.archive.sha256
readonly max_redirects=5
readonly allowed_hosts='dbeaver.io github.com release-assets.githubusercontent.com'

temporary_download=''
staging_root=''
cleanup() {
  [[ -z "$temporary_download" ]] || rm -rf "$temporary_download"
  [[ -z "$staging_root" ]] || rm -rf "$staging_root"
}
trap cleanup EXIT

[[ $# -eq 0 ]] || { echo 'prepare-dbeaver-target.sh accepts no arguments' >&2; exit 2; }
[[ -f "$digest_file" ]] || { echo "missing committed digest: $digest_file" >&2; exit 1; }
digest=$(tr -d '\r\n' < "$digest_file")
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
if url.scheme != "https" or url.hostname not in allowed or url.username or url.password:
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
        location=$(sed -n 's/^[Ll]ocation:[[:space:]]*//p' "$response_dir/headers" | tr -d '\r')
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

mkdir -p "$cache_dir"
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

if [[ -d "$install" && -f "$install_marker" && "$(cat "$install_marker")" == "$digest" ]]; then
  echo "reusing prepared installation: $install"
  exit 0
fi

[[ ! -e "$install_root" ]] || {
  echo "replacing incomplete or unverified installation: $install_root"
  rm -rf "$install_root"
}
staging_root=$(mktemp -d ".cache/.dbeaver-${version}.staging.XXXXXX")
tar -xzf "$archive" -C "$staging_root"
[[ -d "$staging_root/dbeaver/plugins" ]] || {
  echo 'archive did not contain a complete dbeaver installation' >&2
  exit 1
}
printf '%s\n' "$digest" > "$staging_root/.archive.sha256"
mv "$staging_root" "$install_root"
staging_root=''
echo "prepared DBeaver target: $install"
