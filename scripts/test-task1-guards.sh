#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"
temporary=$(mktemp -d)
foreign_lock=''
foreign_lock_owned=false
suite_cache_backup=$temporary/cache.original
cache_archive_seed=$temporary/cache-archive.seed
had_cache=false
cleanup_done=false
tracked_saved=false
cache_saved=false

cleanup() {
  local status=$?
  if [[ "$cleanup_done" == true ]]; then
    return "$status"
  fi
  cleanup_done=true
  trap - EXIT INT TERM HUP
  if [[ "$foreign_lock_owned" == true && -n "$foreign_lock" ]]; then
    rm -rf "$foreign_lock" 2>/dev/null || true
  fi
  if [[ "$cache_saved" == true ]]; then
    rm -rf .cache 2>/dev/null || true
    if [[ "$had_cache" == true && ( -e "$suite_cache_backup" || -L "$suite_cache_backup" ) ]]; then
      mv "$suite_cache_backup" .cache
    fi
  fi
  if [[ "$tracked_saved" == true ]]; then
    for tracked in mvnw .mvn/wrapper/maven-wrapper.properties \
      releng/baseline/dbeaver-ce-26.1.0-linux-x86_64.tar.gz.sha256; do
      cp -p "$temporary/tracked/$tracked" "$tracked" 2>/dev/null || true
    done
  fi
  rm -rf "$temporary"
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

for tracked in mvnw .mvn/wrapper/maven-wrapper.properties \
  releng/baseline/dbeaver-ce-26.1.0-linux-x86_64.tar.gz.sha256; do
  mkdir -p "$temporary/tracked/$(dirname "$tracked")"
  cp -p "$tracked" "$temporary/tracked/$tracked"
done
tracked_saved=true
if [[ -e .cache || -L .cache ]]; then
  had_cache=true
  python3 - "$cache_archive_seed" <<'PY'
import hashlib
from pathlib import Path
import shutil
import stat
import sys

source = Path(".cache/downloads/dbeaver-ce-26.1.0-linux-x86_64.tar.gz")
expected_file = Path("releng/baseline/dbeaver-ce-26.1.0-linux-x86_64.tar.gz.sha256")
if source.exists() and all(not part.is_symlink() for part in (Path(".cache"), source.parent)):
    status = source.lstat()
    expected = expected_file.read_text(encoding="ascii").strip()
    if stat.S_ISREG(status.st_mode) and status.st_nlink == 1:
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if digest == expected:
            shutil.copyfile(source, sys.argv[1])
PY
  cache_saved=true
  mv .cache "$suite_cache_backup"
fi
cache_saved=true
mkdir .cache
if [[ -f "$cache_archive_seed" ]]; then
  mkdir .cache/downloads
  cp "$cache_archive_seed" .cache/downloads/dbeaver-ce-26.1.0-linux-x86_64.tar.gz
fi

if [[ ${TASK1_GUARD_TEST_FAIL_SETUP:-0} == 1 ]]; then
  echo 'forced setup failure' >&2
  exit 74
fi

if [[ ${1:-} == --transaction-self-test-child || ${1:-} == --transaction-signal-child \
    || ${1:-} == --transaction-owned-lock-child ]]; then
  printf 'transaction mutation reached\n' >&2
  chmod 0600 mvnw
  printf '\nmutated\n' >> .mvn/wrapper/maven-wrapper.properties
  printf '\nmutated\n' >> releng/baseline/dbeaver-ce-26.1.0-linux-x86_64.tar.gz.sha256
  mkdir -p .cache/transaction-child
  printf 'mutated\n' > .cache/transaction-child/value
  [[ ! -f .cache/dbeaver-26.1.0/dbeaver/dbeaver.ini ]] || \
    printf '\nmutated\n' >> .cache/dbeaver-26.1.0/dbeaver/dbeaver.ini
  if [[ ${1:-} == --transaction-signal-child ]]; then
    kill -TERM $$
  elif [[ ${1:-} == --transaction-owned-lock-child ]]; then
    foreign_lock=.cache/.prepare-dbeaver-26.1.0.lock
    foreign_lock_owned=true
    mkdir "$foreign_lock"
    printf 'owned\n' > "$foreign_lock/owner"
  fi
  exit 73
elif [[ $# -ne 0 ]]; then
  echo 'unsupported guard-suite argument' >&2
  exit 2
fi

state_fingerprint() {
  python3 - <<'PY'
import hashlib
from pathlib import Path
import stat
for root in (Path("mvnw"), Path(".mvn/wrapper/maven-wrapper.properties"),
             Path("releng/baseline/dbeaver-ce-26.1.0-linux-x86_64.tar.gz.sha256"), Path(".cache")):
    if not root.exists() and not root.is_symlink():
        print(root.as_posix(), "missing")
        continue
    status = root.lstat()
    paths = [root] if not stat.S_ISDIR(status.st_mode) else [root, *sorted(root.rglob("*"))]
    for path in paths:
        status = path.lstat()
        value = [path.as_posix(), oct(stat.S_IMODE(status.st_mode)), str(stat.S_IFMT(status.st_mode))]
        if stat.S_ISREG(status.st_mode):
            value.append(hashlib.sha256(path.read_bytes()).hexdigest())
        elif stat.S_ISLNK(status.st_mode):
            value.append(path.readlink().as_posix())
        print("\0".join(value))
PY
}

assert_forced_restore() {
  local label=$1
  local expected_status=$2
  local marker=$3
  shift 3
  state_fingerprint | sha256sum > "$temporary/$label.before"
  git diff --binary | sha256sum >> "$temporary/$label.before"
  git status --porcelain=v1 >> "$temporary/$label.before"
  set +e
  "$@" >"$temporary/$label.transaction.out" 2>&1
  local actual_status=$?
  set -e
  if [[ "$actual_status" -ne "$expected_status" ]]; then
    cat "$temporary/$label.transaction.out" >&2
    echo "unexpected transaction status: $label expected=$expected_status actual=$actual_status" >&2
    exit 1
  fi
  if [[ -n "$marker" ]] && ! rg -q "$marker" "$temporary/$label.transaction.out"; then
    cat "$temporary/$label.transaction.out" >&2
    echo "transaction point not reached: $label" >&2
    exit 1
  fi
  if [[ "$actual_status" -eq 0 ]]; then
    echo "forced transaction failure unexpectedly succeeded: $label" >&2
    exit 1
  fi
  state_fingerprint | sha256sum > "$temporary/$label.after"
  git diff --binary | sha256sum >> "$temporary/$label.after"
  git status --porcelain=v1 >> "$temporary/$label.after"
  diff -u "$temporary/$label.before" "$temporary/$label.after"
  echo "negative guard passed: $label restored exact caller state"
}

assert_forced_restore transaction-child 73 'transaction mutation reached' \
  bash scripts/test-task1-guards.sh --transaction-self-test-child
assert_forced_restore transaction-signal 143 'transaction mutation reached' \
  bash scripts/test-task1-guards.sh --transaction-signal-child
assert_forced_restore setup-failure 74 'forced setup failure' \
  env TASK1_GUARD_TEST_FAIL_SETUP=1 bash scripts/test-task1-guards.sh
assert_forced_restore owned-lock-cleanup 73 'transaction mutation reached' \
  bash scripts/test-task1-guards.sh --transaction-owned-lock-child

mkdir -p "$temporary/mv-wrapper"
real_mv=$(command -v mv)
cat > "$temporary/mv-wrapper/mv" <<EOF
#!/usr/bin/env bash
"$real_mv" "\$@"
if [[ \${1:-} == .cache && ! -e "$temporary/post-move.reached" ]]; then
  printf 'post-move reached\n' > "$temporary/post-move.reached"
  kill -TERM "\$PPID"
fi
EOF
chmod +x "$temporary/mv-wrapper/mv"
assert_forced_restore post-move-signal 143 '' \
  env PATH="$temporary/mv-wrapper:$PATH" bash scripts/test-task1-guards.sh --transaction-self-test-child
test "$(cat "$temporary/post-move.reached")" = 'post-move reached'

rm -rf .cache
assert_forced_restore absent-cache 73 'transaction mutation reached' \
  bash scripts/test-task1-guards.sh --transaction-self-test-child
test ! -e .cache && test ! -L .cache
mkdir .cache

rm -rf .cache
mkdir -p "$temporary/outside-valid"
printf 'outside sentinel\n' > "$temporary/outside-valid/sentinel"
ln -s "$temporary/outside-valid" .cache
assert_forced_restore valid-cache-symlink 73 'transaction mutation reached' \
  bash scripts/test-task1-guards.sh --transaction-self-test-child
test "$(cat "$temporary/outside-valid/sentinel")" = 'outside sentinel'
rm .cache
ln -s "$temporary/missing-cache-target" .cache
assert_forced_restore broken-cache-symlink 73 'transaction mutation reached' \
  bash scripts/test-task1-guards.sh --transaction-self-test-child
rm .cache
mkdir -p .cache "$temporary/outside-nested"
printf 'outside nested sentinel\n' > "$temporary/outside-nested/sentinel"
ln -s "$temporary/outside-nested" .cache/transaction-child
state_fingerprint | sha256sum > "$temporary/nested-valid.before"
find "$temporary/outside-nested" -printf '%y %m %s %p %l\n' -exec sha256sum {} \; 2>/dev/null | sha256sum \
  >> "$temporary/nested-valid.before"
assert_forced_restore nested-valid-cache-symlink 73 'transaction mutation reached' \
  bash scripts/test-task1-guards.sh --transaction-self-test-child
state_fingerprint | sha256sum > "$temporary/nested-valid.after"
find "$temporary/outside-nested" -printf '%y %m %s %p %l\n' -exec sha256sum {} \; 2>/dev/null | sha256sum \
  >> "$temporary/nested-valid.after"
diff -u "$temporary/nested-valid.before" "$temporary/nested-valid.after"
rm -rf .cache
mkdir -p .cache
ln -s "$temporary/missing-nested-target" .cache/transaction-child
assert_forced_restore nested-broken-cache-symlink 73 'transaction mutation reached' \
  bash scripts/test-task1-guards.sh --transaction-self-test-child
rm -rf .cache
mkdir -p .cache/.prepare-dbeaver-26.1.0.lock
assert_forced_restore foreign-lock-transaction 73 'transaction mutation reached' \
  bash scripts/test-task1-guards.sh --transaction-self-test-child
test -d .cache/.prepare-dbeaver-26.1.0.lock
rm -rf .cache
mkdir .cache

expect_failure() {
  local label=$1
  shift
  if "$@" >"$temporary/$label.out" 2>&1; then
    echo "expected failure: $label" >&2
    cat "$temporary/$label.out" >&2
    exit 1
  fi
  echo "negative guard passed: $label"
}

mkdir -p "$temporary/no-rg-bin"
ln -s "$(command -v bash)" "$temporary/no-rg-bin/bash"
expect_failure scanner-unavailable env PATH="$temporary/no-rg-bin" bash scripts/verify-layout.sh

chmod -x mvnw
expect_failure wrapper-not-executable bash scripts/verify-layout.sh
chmod +x mvnw

cp .mvn/wrapper/maven-wrapper.properties "$temporary/wrapper.properties"
printf '\ndistributionUrl=https://example.invalid/latest.zip\n' >> .mvn/wrapper/maven-wrapper.properties
expect_failure wrapper-properties bash scripts/bootstrap-workspace.sh
mv "$temporary/wrapper.properties" .mvn/wrapper/maven-wrapper.properties

checksum=releng/baseline/dbeaver-ce-26.1.0-linux-x86_64.tar.gz.sha256
cp "$checksum" "$temporary/checksum"
cat "$temporary/checksum" >> "$checksum"
expect_failure multiple-digest-lines bash scripts/prepare-dbeaver-target.sh
mv "$temporary/checksum" "$checksum"

bash scripts/bootstrap-workspace.sh >/dev/null
install=.cache/dbeaver-26.1.0/dbeaver
install_root=.cache/dbeaver-26.1.0
archive=.cache/downloads/dbeaver-ce-26.1.0-linux-x86_64.tar.gz
digest=$(cat "$checksum")

launcher_mode=$(stat -c '%a' "$install/dbeaver")
jre_mode=$(stat -c '%a' "$install/jre/bin/java")
regular=$install/configuration/config.ini
regular_mode=$(stat -c '%a' "$regular")
directory=$install/plugins
directory_mode=$(stat -c '%a' "$directory")
root_mode=$(stat -c '%a' "$install")
for mode_case in \
  "launcher|$install/dbeaver|dbeaver|$launcher_mode|0644" \
  "jre|$install/jre/bin/java|jre/bin/java|$jre_mode|0644" \
  "regular|$regular|configuration/config.ini|$regular_mode|0600" \
  "directory|$directory|plugins|$directory_mode|0700" \
  "root|$install|<root>|$root_mode|0700"; do
  IFS='|' read -r label path relative expected_mode drift_mode <<< "$mode_case"
  chmod "$drift_mode" "$path"
  expect_failure "installed-mode-$label" \
    python3 scripts/verify-dbeaver-tree.py "$archive" "$install" "$digest"
  rg -q "mode mismatch: path=$relative expected=0*$expected_mode actual=0*$drift_mode" \
    "$temporary/installed-mode-$label.out"
  bash scripts/prepare-dbeaver-target.sh >"$temporary/mode-repair-$label.out"
  test "$(stat -c '%a' "$path")" = "$expected_mode"
  echo "negative guard passed: $label mode drift repaired independently"
done

(
  trap 'chmod "$launcher_mode" "$install/dbeaver"' EXIT
  chmod 0644 "$install/dbeaver"
  expect_failure launcher-not-executable bash scripts/verify-dbeaver-baseline.sh
  rg -q 'DBeaver launcher is not executable' "$temporary/launcher-not-executable.out"
)
(
  trap 'chmod "$jre_mode" "$install/jre/bin/java"' EXIT
  chmod 0644 "$install/jre/bin/java"
  expect_failure jre-not-executable bash scripts/verify-dbeaver-baseline.sh
  rg -q 'bundled DBeaver JRE is not executable' "$temporary/jre-not-executable.out"
)
mkdir "$temporary/drift-javap"
real_javap=$(command -v javap)
cat > "$temporary/drift-javap/javap" <<EOF
#!/usr/bin/env bash
"$real_javap" "\$@" | sed '/hidePresentation(org.jkiss.dbeaver.ui.editors.sql.SQLEditor);/d'
EOF
chmod +x "$temporary/drift-javap/javap"
expect_failure api-contract-drift env PATH="$temporary/drift-javap:$PATH" bash scripts/verify-dbeaver-baseline.sh
rg -q 'SQLEditorPresentation public API contract drifted' "$temporary/api-contract-drift.out"
echo 'negative guards passed: executable and public API contract diagnostics'

foreign_lock=.cache/.prepare-dbeaver-26.1.0.lock
mkdir "$foreign_lock"
expect_failure foreign-lock-preserved bash scripts/prepare-dbeaver-target.sh
rg -q 'another DBeaver preparation is active' "$temporary/foreign-lock-preserved.out"
test -d "$foreign_lock"
if mkdir "$foreign_lock" 2>/dev/null; then
  echo 'foreign preparation lock became acquirable' >&2
  exit 1
fi
rmdir "$foreign_lock"
foreign_lock=''
echo 'negative guard passed: failed acquisition preserved foreign lock ownership'

python3 - "$install/dbeaver.ini" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = bytearray(path.read_bytes())
data[0] ^= 1
path.write_bytes(data)
PY
bash scripts/prepare-dbeaver-target.sh >"$temporary/modified.out"
python3 scripts/verify-dbeaver-tree.py "$archive" "$install" "$digest" >/dev/null
rg -q 'replacing incomplete or unverified installation' "$temporary/modified.out"
echo 'negative guard passed: modified installed file repaired'

printf 'extra\n' > "$install/plugins/extra-test-bundle.jar"
bash scripts/prepare-dbeaver-target.sh >"$temporary/extra.out"
python3 scripts/verify-dbeaver-tree.py "$archive" "$install" "$digest" >/dev/null
rg -q 'replacing incomplete or unverified installation' "$temporary/extra.out"
echo 'negative guard passed: extra installed bundle repaired'

removed=$(find "$install/plugins" -maxdepth 1 -type f -name '*.jar' -print -quit)
rm "$removed"
bash scripts/prepare-dbeaver-target.sh >"$temporary/removed.out"
python3 scripts/verify-dbeaver-tree.py "$archive" "$install" "$digest" >/dev/null
rg -q 'replacing incomplete or unverified installation' "$temporary/removed.out"
echo 'negative guard passed: removed installed file repaired'

ln -s "$temporary/outside-symlink-target" "$install/plugins/installed-symlink"
expect_failure installed-symlink python3 scripts/verify-dbeaver-tree.py "$archive" "$install" "$digest"
rm "$install/plugins/installed-symlink"
mkfifo "$install/plugins/installed-special"
expect_failure installed-special python3 scripts/verify-dbeaver-tree.py "$archive" "$install" "$digest"
rm "$install/plugins/installed-special"
echo 'negative guards passed: installed symlink and special entry rejected'

linked=$(find "$install/plugins" -maxdepth 1 -type f -name '*.jar' -print -quit)
outside_link=$temporary/outside-hardlink
ln "$linked" "$outside_link"
outside_digest=$(sha256sum "$outside_link")
expect_failure installed-hardlink python3 scripts/verify-dbeaver-tree.py "$archive" "$install" "$digest"
rg -q 'installed hardlink is forbidden' "$temporary/installed-hardlink.out"
bash scripts/prepare-dbeaver-target.sh >"$temporary/hardlink-repair.out"
test "$(sha256sum "$outside_link")" = "$outside_digest"
test "$(stat -c %h "$outside_link")" -eq 1
python3 scripts/verify-dbeaver-tree.py "$archive" "$install" "$digest" >/dev/null
echo 'negative guard passed: installed hardlink repaired without outside mutation'

python3 - "$temporary" <<'PY'
import io
import gzip
from pathlib import Path
import sys
import tarfile

root = Path(sys.argv[1])

def archive(name, entries):
    with tarfile.open(root / name, "w:gz", format=tarfile.GNU_FORMAT) as target:
        for path, kind, data in entries:
            info = tarfile.TarInfo(path)
            if kind == "dir":
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                target.addfile(info)
            elif kind == "file":
                info.mode = 0o644
                info.size = len(data)
                target.addfile(info, io.BytesIO(data))
            elif kind == "symlink":
                info.type = tarfile.SYMTYPE
                info.linkname = "../../outside"
                target.addfile(info)
            elif kind == "hardlink":
                info.type = tarfile.LNKTYPE
                info.linkname = "dbeaver/a"
                target.addfile(info)
            elif kind == "special":
                info.type = tarfile.FIFOTYPE
                target.addfile(info)
            elif kind == "contiguous":
                info.type = tarfile.CONTTYPE
                info.size = len(data)
                target.addfile(info, io.BytesIO(data))

archive("duplicate-root.tar.gz", [("dbeaver/", "dir", b""), ("dbeaver/", "dir", b""),
                                  ("dbeaver/a", "file", b"a")])
archive("missing-root.tar.gz", [("dbeaver/a", "file", b"a")])
archive("empty-root.tar.gz", [("dbeaver/", "dir", b"")])
archive("unsafe-late.tar.gz", [("dbeaver/", "dir", b""), ("dbeaver/a", "file", b"a"),
                               ("dbeaver/link", "symlink", b"")])
base = [("dbeaver/", "dir", b""), ("dbeaver/a", "file", b"a")]
archive("file-slash.tar.gz", [("dbeaver/", "dir", b""), ("dbeaver/a/", "file", b"a")])
archive("file-slash-collision.tar.gz", [("dbeaver/", "dir", b""), ("dbeaver/a/", "dir", b""),
                                           ("dbeaver/a/", "file", b"a")])
archive("root-file-slash.tar.gz", [("dbeaver/", "dir", b""), ("dbeaver/", "file", b"a")])
archive("root-no-slash.tar.gz", [("dbeaver", "dir", b""), ("dbeaver/a", "file", b"a")])
archive("hardlink.tar.gz", base + [("dbeaver/hard", "hardlink", b"")])
archive("special.tar.gz", base + [("dbeaver/fifo", "special", b"")])
archive("absolute.tar.gz", base + [("/dbeaver/absolute", "file", b"x")])
archive("traversal.tar.gz", base + [("dbeaver/../outside", "file", b"x")])
archive("duplicate-path.tar.gz", base + [("dbeaver/a", "file", b"a")])
archive("contiguous.tar.gz", [("dbeaver/", "dir", b""), ("dbeaver/a", "contiguous", b"a")])
archive("missing-parent.tar.gz", [("dbeaver/", "dir", b""), ("dbeaver/a/b", "file", b"b")])
archive("file-ancestor-first.tar.gz", base + [("dbeaver/a/b", "file", b"b")])
archive("file-ancestor-last.tar.gz", [("dbeaver/", "dir", b""), ("dbeaver/a/b", "file", b"b"),
                                         ("dbeaver/a", "file", b"a")])
archive("identity-collision.tar.gz", [("dbeaver/", "dir", b""), ("dbeaver/a/", "dir", b""),
                                      ("dbeaver/a", "file", b"a")])
long_directory = "dbeaver/" + "canonical-long-directory-" * 5
long_file = long_directory + "/" + "canonical-long-file-" * 5
archive("longlink-valid.tar.gz", [("dbeaver/", "dir", b""), (long_directory + "/", "dir", b""),
                                  (long_file, "file", b"long")])

root_alias = root / "root-no-slash.tar.gz"
with gzip.open(root_alias, "rb") as source:
    payload = bytearray(source.read())
payload[:100] = b"dbeaver\0" + b"\0" * 92
payload[148:156] = b"        "
payload[148:156] = f"{sum(payload[:512]):06o}\0 ".encode("ascii")
with gzip.open(root_alias, "wb") as target:
    target.write(payload)
PY
for fixture in duplicate-root missing-root empty-root unsafe-late file-slash file-slash-collision root-file-slash \
  root-no-slash hardlink special absolute traversal \
  duplicate-path contiguous missing-parent file-ancestor-first file-ancestor-last identity-collision; do
  destination=$temporary/$fixture-output
  expect_failure "archive-$fixture" python3 scripts/verify-dbeaver-tree.py --extract \
    "$temporary/$fixture.tar.gz" "$destination" "$(sha256sum "$temporary/$fixture.tar.gz" | cut -d' ' -f1)"
  test ! -e "$destination"
done
destination=$temporary/digest-mismatch-output
expect_failure archive-digest-mismatch python3 scripts/verify-dbeaver-tree.py --extract \
  "$temporary/duplicate-path.tar.gz" "$destination" "$(printf '0%.0s' {1..64})"
test ! -e "$destination"
destination=$temporary/longlink-valid-output
(umask 077; python3 scripts/verify-dbeaver-tree.py --extract "$temporary/longlink-valid.tar.gz" "$destination" \
  "$(sha256sum "$temporary/longlink-valid.tar.gz" | cut -d' ' -f1)" >/dev/null)
long_output_directory=$destination/$(printf 'canonical-long-directory-%.0s' {1..5})
long_output_file=$long_output_directory/$(printf 'canonical-long-file-%.0s' {1..5})
test "$(stat -c '%a' "$long_output_directory")" = 755
test "$(stat -c '%a' "$long_output_file")" = 644
test "$(stat -c '%a' "$destination")" = 755
test "$(cat "$long_output_file")" = long
echo 'positive guard passed: canonical GNU LongLink directory and file extracted'

cp "$temporary/longlink-valid.tar.gz" "$temporary/snapshot-source.tar.gz"
snapshot_digest=$(sha256sum "$temporary/snapshot-source.tar.gz" | cut -d' ' -f1)
snapshot_destination=$temporary/snapshot-output
python3 - "$temporary/snapshot-source.tar.gz" "$snapshot_destination" "$snapshot_digest" <<'PY'
import importlib.util
from pathlib import Path
import sys
import tarfile

source_path, destination, digest = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
spec = importlib.util.spec_from_file_location("tree_verifier", "scripts/verify-dbeaver-tree.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
snapshots = module.verified_snapshot(source_path, digest)
snapshot = next(snapshots)
source_path.write_bytes(b"mutated original archive\n")
with tarfile.open(fileobj=snapshot, mode="r:gz") as archive:
    records, expected = module.validated_members(archive)
    module.extract_members(archive, records, destination)
assert module.installed_manifest(destination) == expected
snapshots.close()
PY
test "$(cat "$snapshot_destination/$(printf 'canonical-long-directory-%.0s' {1..5})/$(printf 'canonical-long-file-%.0s' {1..5})")" = long
echo 'positive guard passed: verified private snapshot resisted source mutation'
echo 'negative guards passed: unsafe archives rejected before materialization'

printf 'force rebuild\n' >> "$install/dbeaver.ini"
python3 - "$install_root" > "$temporary/transaction-before" <<'PY'
import hashlib, os, stat, sys
from pathlib import Path
root = Path(sys.argv[1])
for path in sorted(root.rglob("*")):
    status = path.lstat()
    relative = path.relative_to(root).as_posix()
    if stat.S_ISREG(status.st_mode):
        print("file", relative, oct(stat.S_IMODE(status.st_mode)), hashlib.sha256(path.read_bytes()).hexdigest())
    elif stat.S_ISDIR(status.st_mode):
        print("directory", relative, oct(stat.S_IMODE(status.st_mode)))
    elif stat.S_ISLNK(status.st_mode):
        print("symlink", relative, os.readlink(path))
    else:
        print("special", relative, status.st_mode)
PY
expect_failure publication-rollback env DBEAVER_PREPARE_TEST_FAIL_PUBLISH=1 bash scripts/prepare-dbeaver-target.sh
python3 - "$install_root" > "$temporary/transaction-after" <<'PY'
import hashlib, os, stat, sys
from pathlib import Path
root = Path(sys.argv[1])
for path in sorted(root.rglob("*")):
    status = path.lstat()
    relative = path.relative_to(root).as_posix()
    if stat.S_ISREG(status.st_mode):
        print("file", relative, oct(stat.S_IMODE(status.st_mode)), hashlib.sha256(path.read_bytes()).hexdigest())
    elif stat.S_ISDIR(status.st_mode):
        print("directory", relative, oct(stat.S_IMODE(status.st_mode)))
    elif stat.S_ISLNK(status.st_mode):
        print("symlink", relative, os.readlink(path))
    else:
        print("special", relative, status.st_mode)
PY
diff -u "$temporary/transaction-before" "$temporary/transaction-after"
test -z "$(find .cache -maxdepth 1 \( -name '.dbeaver-*.staging.*' -o -name '.dbeaver-*.previous.*' \) -print -quit)"
echo 'negative guard passed: failed publication restored previous installation'
bash scripts/prepare-dbeaver-target.sh >/dev/null

find .cache/dbeaver-26.1.0 -printf '%P %m %s %T@\n' | sort | sha256sum > "$temporary/tree-before"
bash scripts/prepare-dbeaver-target.sh >"$temporary/reuse.out"
find .cache/dbeaver-26.1.0 -printf '%P %m %s %T@\n' | sort | sha256sum > "$temporary/tree-after"
diff -u "$temporary/tree-before" "$temporary/tree-after"
rg -q 'reusing exact verified installation' "$temporary/reuse.out"
echo 'positive guard passed: clean installation reused without mutation'

cache_escape_backup=$temporary/cache-escape-backup
mv .cache "$cache_escape_backup"
mkdir "$temporary/outside-cache"
printf 'outside sentinel\n' > "$temporary/outside-cache/sentinel"
ln -s "$temporary/outside-cache" .cache
expect_failure cache-symlink-escape bash scripts/prepare-dbeaver-target.sh
test "$(cat "$temporary/outside-cache/sentinel")" = 'outside sentinel'
test "$(find "$temporary/outside-cache" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1
rm .cache
mv "$cache_escape_backup" .cache
echo 'negative guard passed: cache symlink escape preserved outside sentinel'

for escape in downloads installation archive; do (
  outside=$temporary/outside-$escape
  mkdir "$outside"
  printf 'outside sentinel\n' > "$outside/sentinel"
  case "$escape" in
    downloads)
      protected=.cache/downloads
      ;;
    installation)
      protected=.cache/dbeaver-26.1.0
      ;;
    archive)
      protected=.cache/downloads/dbeaver-ce-26.1.0-linux-x86_64.tar.gz
      ;;
  esac
  saved=$temporary/saved-$escape
  mv "$protected" "$saved"
  restore_escape() {
    [[ ! -L "$protected" ]] || rm "$protected"
    [[ ! -e "$protected" ]] || mv "$protected" "$temporary/unexpected-$escape"
    [[ ! -e "$saved" ]] || mv "$saved" "$protected"
  }
  trap restore_escape EXIT
  ln -s "$outside" "$protected"
  expect_failure "$escape-symlink-escape" bash scripts/prepare-dbeaver-target.sh
  test "$(cat "$outside/sentinel")" = 'outside sentinel'
  test "$(find "$outside" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1
  rm "$protected"
  mv "$saved" "$protected"
  trap - EXIT
); done
echo 'negative guards passed: cache child symlink escapes preserved outside sentinels'

repository=repository/target/repository
production_target=releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.target/io.github.bakhtiiartashbolotov.dbeaver.monaco.target.target
test_target=releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target/io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target.target

cp "$test_target" "$temporary/vintage.target"
python3 - "$temporary/vintage.target" <<'PY'
import sys
import xml.etree.ElementTree as ET
path = sys.argv[1]
tree = ET.parse(path)
dependencies = tree.getroot().find("./locations/location[@type='Maven']/dependencies")
entry = ET.SubElement(dependencies, "dependency")
for name, value in (("groupId", "org.junit.vintage"), ("artifactId", "junit-vintage-engine"), ("version", "5.13.4")):
    ET.SubElement(entry, name).text = value
tree.write(path, encoding="utf-8", xml_declaration=True)
PY
expect_failure vintage-root bash scripts/verify-test-target.sh "$repository" "$production_target" "$temporary/vintage.target"

cp "$test_target" "$temporary/duplicate.target"
python3 - "$temporary/duplicate.target" <<'PY'
import copy
import sys
import xml.etree.ElementTree as ET
path = sys.argv[1]
tree = ET.parse(path)
dependencies = tree.getroot().find("./locations/location[@type='Maven']/dependencies")
dependencies.append(copy.deepcopy(dependencies[0]))
tree.write(path, encoding="utf-8", xml_declaration=True)
PY
expect_failure duplicate-root bash scripts/verify-test-target.sh "$repository" "$production_target" "$temporary/duplicate.target"

for mutation in wrong-root extra-root-sibling wrong-location-tag directory-child dependency-child dependency-attribute; do
  cp "$test_target" "$temporary/$mutation.target"
  python3 - "$temporary/$mutation.target" "$mutation" <<'PY'
import sys
import xml.etree.ElementTree as ET
path, mutation = sys.argv[1:]
tree = ET.parse(path)
root = tree.getroot()
locations = root.find("locations")
directory = locations.find("location[@type='Directory']")
dependencies = locations.find("location[@type='Maven']/dependencies")
if mutation == "wrong-root":
    root.tag = "other"
elif mutation == "extra-root-sibling":
    ET.SubElement(root, "locations")
elif mutation == "wrong-location-tag":
    directory.tag = "other"
elif mutation == "directory-child":
    ET.SubElement(directory, "unexpected")
elif mutation == "dependency-child":
    ET.SubElement(dependencies, "unexpected")
else:
    dependencies[0].set("optional", "false")
tree.write(path, encoding="utf-8", xml_declaration=True)
PY
  expect_failure "target-$mutation" bash scripts/verify-test-target.sh \
    "$repository" "$production_target" "$temporary/$mutation.target"
done

cp -a "$repository" "$temporary/exploded-repository"
mkdir "$temporary/exploded-repository/plugins/injected.tests"
expect_failure exploded-test-plugin bash scripts/verify-test-target.sh "$temporary/exploded-repository" "$production_target" "$test_target"

cp -a "$repository" "$temporary/feature-repository"
python3 - "$temporary/feature-repository" <<'PY'
import os
import lzma
from pathlib import Path
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
repo = Path(sys.argv[1])
feature_jar = next((repo / "features").glob("*.jar"))
with zipfile.ZipFile(feature_jar) as source:
    files = {name: source.read(name) for name in source.namelist()}
root = ET.fromstring(files["feature.xml"])
ET.SubElement(root, "plugin", {"id": "junit-platform-suite-engine", "version": "0.0.0"})
files["feature.xml"] = ET.tostring(root, encoding="utf-8", xml_declaration=True)
temporary = feature_jar.with_suffix(".tmp")
with zipfile.ZipFile(temporary, "w") as target:
    for name, data in files.items():
        target.writestr(name, data)
os.replace(temporary, feature_jar)
PY
expect_failure packaged-feature-test-plugin bash scripts/verify-test-target.sh "$temporary/feature-repository" "$production_target" "$test_target"

for mutation in feature-version artifact-version unit-version capability-version capability-duplicate; do
  cp -a "$repository" "$temporary/p2-$mutation"
  python3 - "$temporary/p2-$mutation" "$mutation" <<'PY'
import lzma
import os
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile

repo, mutation = Path(sys.argv[1]), sys.argv[2]

def rewrite(path, member, mutate):
    with zipfile.ZipFile(path) as source:
        files = {name: source.read(name) for name in source.namelist()}
    root = ET.fromstring(files[member])
    mutate(root)
    files[member] = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    replacement = path.with_suffix(".tmp")
    with zipfile.ZipFile(replacement, "w") as target:
        for name, data in files.items():
            target.writestr(name, data)
    os.replace(replacement, path)

def rewrite_metadata(base, mutate):
    xz_path = repo / f"{base}.xml.xz"
    xz_root = ET.fromstring(lzma.decompress(xz_path.read_bytes()))
    mutate(xz_root)
    data = ET.tostring(xz_root, encoding="utf-8", xml_declaration=True)
    xz_path.write_bytes(lzma.compress(data))
    rewrite(repo / f"{base}.jar", f"{base}.xml", mutate)

if mutation == "feature-version":
    feature = next((repo / "features").glob("*.jar"))
    rewrite(feature, "feature.xml", lambda root: root.findall("plugin")[0].set("version", "9.9.9"))
elif mutation == "artifact-version":
    rewrite_metadata("artifacts",
                     lambda root: root.find("./artifacts/artifact[@classifier='osgi.bundle']").set("version", "9.9.9"))
else:
    def content_change(root):
        unit = next(unit for unit in root.findall("./units/unit")
                    if unit.find("./provides/provided[@namespace='osgi.bundle']") is not None)
        capability = unit.find("./provides/provided[@namespace='osgi.bundle']")
        if mutation == "unit-version":
            unit.set("version", "9.9.9")
        elif mutation == "capability-version":
            capability.set("version", "9.9.9")
        else:
            import copy
            unit.find("provides").append(copy.deepcopy(capability))
    rewrite_metadata("content", content_change)
PY
  expect_failure "p2-$mutation" bash scripts/verify-test-target.sh \
    "$temporary/p2-$mutation" "$production_target" "$test_target"
done

for mutation in xz-test-iu xz-test-artifact jar-divergence index-order index-symlink metadata-root \
  metadata-container extra-iu extra-artifact feature-group-edge feature-jar-edge junit-bundle-edge \
  junit-payload optional-group-edge redirected-mapping wrong-units-size wrong-artifacts-size \
  wrong-mappings-size unknown-root-child wrong-feature-artifact wrong-feature-self \
  category-identity extra-bundle-edge missing-group-property required-properties-version \
  required-properties-extra required-properties-remove requires-size provides-size \
  extra-feature-capability artifact-ref-attribute artifact-properties-size feature-junit-payload \
  bundle-require-capability feature-plugin-attribute feature-root feature-import feature-include \
  feature-require unexpected-top-level; do
  cp -a "$repository" "$temporary/closed-p2-$mutation"
  python3 - "$temporary/closed-p2-$mutation" "$mutation" <<'PY'
import lzma
import os
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile

repo, mutation = Path(sys.argv[1]), sys.argv[2]

def read(base, representation):
    if representation == "xz":
        return ET.fromstring(lzma.decompress((repo / f"{base}.xml.xz").read_bytes()))
    with zipfile.ZipFile(repo / f"{base}.jar") as archive:
        return ET.fromstring(archive.read(f"{base}.xml"))

def write(base, representation, root):
    data = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    if representation == "xz":
        (repo / f"{base}.xml.xz").write_bytes(lzma.compress(data))
    else:
        path = repo / f"{base}.jar"
        temporary = path.with_suffix(".tmp")
        with zipfile.ZipFile(temporary, "w") as archive:
            archive.writestr(f"{base}.xml", data)
        os.replace(temporary, path)

def both(base, mutate):
    for representation in ("xz", "jar"):
        root = read(base, representation)
        mutate(root)
        write(base, representation, root)

if mutation == "xz-test-iu":
    root = read("content", "xz")
    ET.SubElement(root.find("units"), "unit", {"id": "junit-platform-engine", "version": "1.13.4"})
    write("content", "xz", root)
elif mutation == "xz-test-artifact":
    root = read("artifacts", "xz")
    ET.SubElement(root.find("artifacts"), "artifact", {
        "classifier": "osgi.bundle", "id": "junit-platform-engine", "version": "1.13.4"})
    write("artifacts", "xz", root)
elif mutation == "jar-divergence":
    root = read("content", "jar")
    root.set("name", "diverged")
    write("content", "jar", root)
elif mutation == "index-order":
    (repo / "p2.index").write_text(
        "version=1\nmetadata.repository.factory.order=content.xml.xz,content.xml,\\!\n"
        "artifact.repository.factory.order=artifacts.xml.xz,artifacts.xml,\\!\n", encoding="utf-8")
elif mutation == "index-symlink":
    real_index = repo.parent / f"{repo.name}.index-real"
    real_index.write_bytes((repo / "p2.index").read_bytes())
    (repo / "p2.index").unlink()
    (repo / "p2.index").symlink_to(f"../{real_index.name}")
elif mutation == "metadata-root":
    both("artifacts", lambda root: setattr(root, "tag", "invalid"))
elif mutation == "metadata-container":
    both("content", lambda root: ET.SubElement(root, "units"))
elif mutation == "extra-iu":
    both("content", lambda root: ET.SubElement(root.find("units"), "unit", {"id": "extra.iu", "version": "1.0.0"}))
elif mutation == "extra-artifact":
    both("artifacts", lambda root: ET.SubElement(root.find("artifacts"), "artifact", {
        "classifier": "binary", "id": "extra.artifact", "version": "1.0.0"}))
elif mutation == "feature-group-edge":
    def add_edge(root):
        group = next(unit for unit in root.findall("./units/unit") if unit.attrib["id"].endswith("feature.group"))
        requires = group.find("requires")
        ET.SubElement(requires, "required", {
            "namespace": "org.eclipse.equinox.p2.iu", "name": "extra.iu", "range": "[1.0.0,1.0.0]"})
        requires.set("size", str(len(requires)))
    both("content", add_edge)
elif mutation == "feature-jar-edge":
    def add_feature_jar_edge(root):
        unit = next(unit for unit in root.findall("./units/unit") if unit.attrib["id"].endswith("feature.jar"))
        requires = unit.find("requires")
        if requires is None:
            requires = ET.SubElement(unit, "requires", {"size": "0"})
        ET.SubElement(requires, "required", {
            "namespace": "org.eclipse.equinox.p2.iu", "name": "extra.iu", "range": "[1.0.0,1.0.0]"})
        requires.set("size", str(len(requires)))
    both("content", add_feature_jar_edge)
elif mutation == "junit-bundle-edge":
    def add_junit_edge(root):
        unit = next(unit for unit in root.findall("./units/unit")
                    if unit.find("./provides/provided[@namespace='osgi.bundle']") is not None)
        requires = unit.find("requires")
        if requires is None:
            requires = ET.SubElement(unit, "requires", {"size": "0"})
        ET.SubElement(requires, "required", {
            "namespace": "org.eclipse.equinox.p2.iu", "name": "junit-platform-engine",
            "range": "[1.13.4,1.13.4]"})
        requires.set("size", str(len(requires)))
    both("content", add_junit_edge)
elif mutation == "junit-payload":
    import hashlib
    plugin = next((repo / "plugins").glob("*core*.jar"))
    with zipfile.ZipFile(plugin) as archive:
        files = {name: archive.read(name) for name in archive.namelist()}
    files["org/junit/JupiterInjected.class"] = b"injected"
    temporary = plugin.with_suffix(".tmp")
    with zipfile.ZipFile(temporary, "w") as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    os.replace(temporary, plugin)
    def update_plugin_hashes(root):
        artifact = next(item for item in root.findall("./artifacts/artifact")
                        if item.attrib.get("id") in plugin.name)
        values = {item.attrib["name"]: item for item in artifact.findall("./properties/property")}
        data = plugin.read_bytes()
        values["artifact.size"].set("value", str(len(data)))
        values["download.size"].set("value", str(len(data)))
        values["download.checksum.sha-256"].set("value", hashlib.sha256(data).hexdigest())
        values["download.checksum.sha-512"].set("value", hashlib.sha512(data).hexdigest())
    both("artifacts", update_plugin_hashes)
elif mutation == "optional-group-edge":
    def optionalize(root):
        group = next(unit for unit in root.findall("./units/unit") if unit.attrib["id"].endswith("feature.group"))
        group.find("./requires/required").set("optional", "true")
    both("content", optionalize)
elif mutation == "redirected-mapping":
    both("artifacts", lambda root: root.find("./mappings/rule").set("output", "${repoUrl}/redirected/${id}"))
elif mutation == "wrong-units-size":
    both("content", lambda root: root.find("units").set("size", "999"))
elif mutation == "wrong-artifacts-size":
    both("artifacts", lambda root: root.find("artifacts").set("size", "999"))
elif mutation == "wrong-mappings-size":
    both("artifacts", lambda root: root.find("mappings").set("size", "999"))
elif mutation == "unknown-root-child":
    both("content", lambda root: ET.SubElement(root, "unknown"))
elif mutation == "wrong-feature-artifact":
    def wrong_feature_artifact(root):
        unit = next(unit for unit in root.findall("./units/unit") if unit.attrib["id"].endswith("feature.jar"))
        unit.find("./artifacts/artifact").set("id", "wrong.feature")
    both("content", wrong_feature_artifact)
elif mutation == "wrong-feature-self":
    def wrong_feature_self(root):
        unit = next(unit for unit in root.findall("./units/unit") if unit.attrib["id"].endswith("feature.jar"))
        unit.find("./provides/provided[@namespace='org.eclipse.equinox.p2.iu']").set("name", "wrong.feature")
    both("content", wrong_feature_self)
elif mutation == "category-identity":
    def wrong_category(root):
        unit = next(unit for unit in root.findall("./units/unit")
                    if unit.find("./properties/property[@name='org.eclipse.equinox.p2.type.category']") is not None)
        unit.set("version", "9.9.9")
    both("content", wrong_category)
elif mutation == "extra-bundle-edge":
    def extra_bundle_edge(root):
        unit = next(unit for unit in root.findall("./units/unit")
                    if unit.find("./provides/provided[@namespace='osgi.bundle']") is not None)
        requires = unit.find("requires")
        ET.SubElement(requires, "required", {
            "namespace": "osgi.bundle", "name": "org.example.extra", "range": "[1.0.0,2.0.0)"})
        requires.set("size", str(len(requires)))
    both("content", extra_bundle_edge)
elif mutation == "missing-group-property":
    def remove_group_property(root):
        group = next(unit for unit in root.findall("./units/unit") if unit.attrib["id"].endswith("feature.group"))
        props = group.find("properties")
        props.remove(props.find("./property[@name='org.eclipse.equinox.p2.type.group']"))
        props.set("size", str(len(props)))
    both("content", remove_group_property)
elif mutation.startswith("required-properties-"):
    def mutate_required_properties(root):
        unit = next(unit for unit in root.findall("./units/unit")
                    if unit.find("./provides/provided[@namespace='osgi.bundle']") is not None)
        requires = unit.find("requires")
        item = requires.find("requiredProperties")
        if mutation == "required-properties-version":
            item.set("match", "(&(osgi.ee=JavaSE)(version=17))")
        elif mutation == "required-properties-remove":
            requires.remove(item)
            requires.set("size", str(len(requires)))
        else:
            import copy
            requires.append(copy.deepcopy(item))
            requires.set("size", str(len(requires)))
    both("content", mutate_required_properties)
elif mutation == "requires-size":
    def wrong_requires_size(root):
        unit = next(unit for unit in root.findall("./units/unit")
                    if unit.find("./provides/provided[@namespace='osgi.bundle']") is not None)
        unit.find("requires").set("size", "999")
    both("content", wrong_requires_size)
elif mutation == "provides-size":
    def wrong_provides_size(root):
        unit = next(unit for unit in root.findall("./units/unit") if unit.attrib["id"].endswith("feature.jar"))
        unit.find("provides").set("size", "999")
    both("content", wrong_provides_size)
elif mutation == "extra-feature-capability":
    def extra_feature_capability(root):
        unit = next(unit for unit in root.findall("./units/unit") if unit.attrib["id"].endswith("feature.jar"))
        provides = unit.find("provides")
        ET.SubElement(provides, "provided", {"namespace": "example", "name": "extra", "version": "1.0.0"})
        provides.set("size", str(len(provides)))
    both("content", extra_feature_capability)
elif mutation == "artifact-ref-attribute":
    def artifact_ref_attribute(root):
        unit = next(unit for unit in root.findall("./units/unit") if unit.attrib["id"].endswith("feature.jar"))
        unit.find("./artifacts/artifact").set("unknown", "true")
    both("content", artifact_ref_attribute)
elif mutation == "artifact-properties-size":
    both("artifacts", lambda root: root.find("./artifacts/artifact/properties").set("size", "999"))
elif mutation in {"feature-junit-payload", "bundle-require-capability"}:
    import hashlib
    if mutation == "feature-junit-payload":
        packaged = next((repo / "features").glob("*.jar"))
        classifier = "org.eclipse.update.feature"
    else:
        packaged = next((repo / "plugins").glob("*core*.jar"))
        classifier = "osgi.bundle"
    with zipfile.ZipFile(packaged) as archive:
        files = {name: archive.read(name) for name in archive.namelist()}
    if mutation == "feature-junit-payload":
        files["org/junit/JupiterInjected.class"] = b"injected"
    else:
        manifest = files["META-INF/MANIFEST.MF"].decode("utf-8")
        files["META-INF/MANIFEST.MF"] = (manifest.rstrip() + "\nRequire-Capability: org.junit.jupiter\n").encode()
    temporary = packaged.with_suffix(".tmp")
    with zipfile.ZipFile(temporary, "w") as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    os.replace(temporary, packaged)
    def update_payload_hashes(root):
        artifact = next(item for item in root.findall("./artifacts/artifact")
                        if item.attrib.get("classifier") == classifier and item.attrib.get("id") in packaged.name)
        values = {item.attrib["name"]: item for item in artifact.findall("./properties/property")}
        data = packaged.read_bytes()
        values["artifact.size"].set("value", str(len(data)))
        values["download.size"].set("value", str(len(data)))
        values["download.checksum.sha-256"].set("value", hashlib.sha256(data).hexdigest())
        values["download.checksum.sha-512"].set("value", hashlib.sha512(data).hexdigest())
    both("artifacts", update_payload_hashes)
elif mutation == "feature-plugin-attribute":
    feature = next((repo / "features").glob("*.jar"))
    with zipfile.ZipFile(feature) as archive:
        files = {name: archive.read(name) for name in archive.namelist()}
    root = ET.fromstring(files["feature.xml"])
    root.find("plugin").set("fragment", "true")
    files["feature.xml"] = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    temporary = feature.with_suffix(".tmp")
    with zipfile.ZipFile(temporary, "w") as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    os.replace(temporary, feature)
    import hashlib
    def update_feature_plugin_hashes(root):
        artifact = root.find("./artifacts/artifact[@classifier='org.eclipse.update.feature']")
        values = {item.attrib["name"]: item for item in artifact.findall("./properties/property")}
        data = feature.read_bytes()
        values["artifact.size"].set("value", str(len(data)))
        values["download.size"].set("value", str(len(data)))
        values["download.checksum.sha-256"].set("value", hashlib.sha256(data).hexdigest())
        values["download.checksum.sha-512"].set("value", hashlib.sha512(data).hexdigest())
    both("artifacts", update_feature_plugin_hashes)
elif mutation == "feature-root":
    feature = next((repo / "features").glob("*.jar"))
    with zipfile.ZipFile(feature) as archive:
        files = {name: archive.read(name) for name in archive.namelist()}
    root = ET.fromstring(files["feature.xml"])
    root.tag = "invalid"
    files["feature.xml"] = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    temporary = feature.with_suffix(".tmp")
    with zipfile.ZipFile(temporary, "w") as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    os.replace(temporary, feature)
    import hashlib
    def update_feature_hashes(root):
        artifact = root.find("./artifacts/artifact[@classifier='org.eclipse.update.feature']")
        values = {item.attrib["name"]: item for item in artifact.findall("./properties/property")}
        data = feature.read_bytes()
        values["artifact.size"].set("value", str(len(data)))
        values["download.size"].set("value", str(len(data)))
        values["download.checksum.sha-256"].set("value", hashlib.sha256(data).hexdigest())
        values["download.checksum.sha-512"].set("value", hashlib.sha512(data).hexdigest())
    both("artifacts", update_feature_hashes)
elif mutation.startswith("feature-"):
    feature = next((repo / "features").glob("*.jar"))
    with zipfile.ZipFile(feature) as archive:
        files = {name: archive.read(name) for name in archive.namelist()}
    root = ET.fromstring(files["feature.xml"])
    ET.SubElement(root, mutation.removeprefix("feature-"))
    files["feature.xml"] = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    temporary = feature.with_suffix(".tmp")
    with zipfile.ZipFile(temporary, "w") as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    os.replace(temporary, feature)
else:
    (repo / "unexpected.xml").write_text("unexpected", encoding="utf-8")
PY
  expect_failure "closed-p2-$mutation" bash scripts/verify-test-target.sh \
    "$temporary/closed-p2-$mutation" "$production_target" "$test_target"
  case "$mutation" in
    junit-payload) rg -q 'test/JUnit marker in production bundle payload' "$temporary/closed-p2-$mutation.out" ;;
    optional-group-edge) rg -q 'unexpected feature.group requirements' "$temporary/closed-p2-$mutation.out" ;;
    redirected-mapping) rg -q 'unexpected artifact mapping rules' "$temporary/closed-p2-$mutation.out" ;;
    wrong-units-size) rg -q 'incorrect units size attribute' "$temporary/closed-p2-$mutation.out" ;;
    wrong-artifacts-size) rg -q 'incorrect artifacts size attribute' "$temporary/closed-p2-$mutation.out" ;;
    wrong-mappings-size) rg -q 'incorrect mappings size attribute' "$temporary/closed-p2-$mutation.out" ;;
    unknown-root-child) rg -q 'unexpected content metadata root children' "$temporary/closed-p2-$mutation.out" ;;
    wrong-feature-artifact) rg -q 'incorrect artifact reference on feature.jar' "$temporary/closed-p2-$mutation.out" ;;
    wrong-feature-self) rg -q 'incorrect feature.jar self capability' "$temporary/closed-p2-$mutation.out" ;;
    category-identity) rg -q 'unexpected category capabilities' "$temporary/closed-p2-$mutation.out" ;;
    extra-bundle-edge) rg -q 'unexpected .* bundle requirements' "$temporary/closed-p2-$mutation.out" ;;
    missing-group-property) rg -q 'missing or invalid feature.group role property' "$temporary/closed-p2-$mutation.out" ;;
    required-properties-version) rg -q 'invalid JavaSE-21 requiredProperties' "$temporary/closed-p2-$mutation.out" ;;
    required-properties-extra) rg -q 'missing JavaSE-21 requiredProperties' "$temporary/closed-p2-$mutation.out" ;;
    required-properties-remove) rg -q 'missing JavaSE-21 requiredProperties' "$temporary/closed-p2-$mutation.out" ;;
    requires-size) rg -q 'incorrect .* requires size attribute' "$temporary/closed-p2-$mutation.out" ;;
    provides-size) rg -q 'incorrect feature.jar provides size attribute' "$temporary/closed-p2-$mutation.out" ;;
    extra-feature-capability) rg -q 'unexpected feature.jar capabilities' "$temporary/closed-p2-$mutation.out" ;;
    artifact-ref-attribute) rg -q 'incorrect artifact reference on feature.jar' "$temporary/closed-p2-$mutation.out" ;;
    artifact-properties-size) rg -q 'incorrect artifact .* properties size attribute' "$temporary/closed-p2-$mutation.out" ;;
    feature-junit-payload) rg -q 'test/JUnit marker in packaged feature payload' "$temporary/closed-p2-$mutation.out" ;;
    bundle-require-capability) rg -q 'test/JUnit marker in production bundle payload or manifest' \
      "$temporary/closed-p2-$mutation.out" ;;
    feature-plugin-attribute) rg -q 'packaged feature plugin identities or structure differ' \
      "$temporary/closed-p2-$mutation.out" ;;
  esac
done

echo 'all Task 1 negative and reuse guards passed'
