#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"
temporary=$(mktemp -d)
cache_backup=''
foreign_lock=''

cleanup() {
  chmod +x mvnw 2>/dev/null || true
  if [[ -n "$cache_backup" && -e "$cache_backup" ]]; then
    rm -rf .cache
    mv "$cache_backup" .cache
  fi
  [[ -z "$foreign_lock" || ! -d "$foreign_lock" ]] || rmdir "$foreign_lock"
  rm -rf "$temporary"
}
trap cleanup EXIT

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
                target.addfile(info)
            elif kind == "file":
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
archive("unsafe-late.tar.gz", [("dbeaver/", "dir", b""), ("dbeaver/a", "file", b"a"),
                               ("dbeaver/link", "symlink", b"")])
base = [("dbeaver/", "dir", b""), ("dbeaver/a", "file", b"a")]
archive("file-slash.tar.gz", [("dbeaver/", "dir", b""), ("dbeaver/a/", "file", b"a")])
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
for fixture in duplicate-root missing-root unsafe-late file-slash root-no-slash hardlink special absolute traversal \
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
python3 scripts/verify-dbeaver-tree.py --extract "$temporary/longlink-valid.tar.gz" "$destination" \
  "$(sha256sum "$temporary/longlink-valid.tar.gz" | cut -d' ' -f1)" >/dev/null
test "$(cat "$destination/$(printf 'canonical-long-directory-%.0s' {1..5})/$(printf 'canonical-long-file-%.0s' {1..5})")" = long
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
        print("file", relative, hashlib.sha256(path.read_bytes()).hexdigest())
    elif stat.S_ISDIR(status.st_mode):
        print("directory", relative)
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
        print("file", relative, hashlib.sha256(path.read_bytes()).hexdigest())
    elif stat.S_ISDIR(status.st_mode):
        print("directory", relative)
    elif stat.S_ISLNK(status.st_mode):
        print("symlink", relative, os.readlink(path))
    else:
        print("special", relative, status.st_mode)
PY
diff -u "$temporary/transaction-before" "$temporary/transaction-after"
test -z "$(find .cache -maxdepth 1 \( -name '.dbeaver-*.staging.*' -o -name '.dbeaver-*.previous.*' \) -print -quit)"
echo 'negative guard passed: failed publication restored previous installation'
bash scripts/prepare-dbeaver-target.sh >/dev/null

find .cache/dbeaver-26.1.0 -printf '%P %s %T@\n' | sort | sha256sum > "$temporary/tree-before"
bash scripts/prepare-dbeaver-target.sh >"$temporary/reuse.out"
find .cache/dbeaver-26.1.0 -printf '%P %s %T@\n' | sort | sha256sum > "$temporary/tree-after"
diff -u "$temporary/tree-before" "$temporary/tree-after"
rg -q 'reusing exact verified installation' "$temporary/reuse.out"
echo 'positive guard passed: clean installation reused without mutation'

cache_backup=$temporary/cache-backup
mv .cache "$cache_backup"
mkdir "$temporary/outside-cache"
printf 'outside sentinel\n' > "$temporary/outside-cache/sentinel"
ln -s "$temporary/outside-cache" .cache
expect_failure cache-symlink-escape bash scripts/prepare-dbeaver-target.sh
test "$(cat "$temporary/outside-cache/sentinel")" = 'outside sentinel'
test "$(find "$temporary/outside-cache" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1
rm .cache
mv "$cache_backup" .cache
cache_backup=''
echo 'negative guard passed: cache symlink escape preserved outside sentinel'

for escape in downloads installation archive; do
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
  ln -s "$outside" "$protected"
  expect_failure "$escape-symlink-escape" bash scripts/prepare-dbeaver-target.sh
  test "$(cat "$outside/sentinel")" = 'outside sentinel'
  test "$(find "$outside" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1
  rm "$protected"
  mv "$saved" "$protected"
done
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

if mutation == "feature-version":
    feature = next((repo / "features").glob("*.jar"))
    rewrite(feature, "feature.xml", lambda root: root.findall("plugin")[0].set("version", "9.9.9"))
elif mutation == "artifact-version":
    rewrite(repo / "artifacts.jar", "artifacts.xml",
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
    rewrite(repo / "content.jar", "content.xml", content_change)
PY
  expect_failure "p2-$mutation" bash scripts/verify-test-target.sh \
    "$temporary/p2-$mutation" "$production_target" "$test_target"
done

echo 'all Task 1 negative and reuse guards passed'
