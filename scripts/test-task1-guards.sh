#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"
temporary=$(mktemp -d)
cache_backup=''

cleanup() {
  chmod +x mvnw 2>/dev/null || true
  if [[ -n "$cache_backup" && -e "$cache_backup" ]]; then
    rm -rf .cache
    mv "$cache_backup" .cache
  fi
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
archive=.cache/downloads/dbeaver-ce-26.1.0-linux-x86_64.tar.gz

printf 'changed\n' >> "$install/dbeaver.ini"
bash scripts/prepare-dbeaver-target.sh >"$temporary/modified.out"
python3 scripts/verify-dbeaver-tree.py "$archive" "$install" >/dev/null
rg -q 'replacing incomplete or unverified installation' "$temporary/modified.out"
echo 'negative guard passed: modified installed file repaired'

printf 'extra\n' > "$install/plugins/extra-test-bundle.jar"
bash scripts/prepare-dbeaver-target.sh >"$temporary/extra.out"
python3 scripts/verify-dbeaver-tree.py "$archive" "$install" >/dev/null
rg -q 'replacing incomplete or unverified installation' "$temporary/extra.out"
echo 'negative guard passed: extra installed bundle repaired'

removed=$(find "$install/plugins" -maxdepth 1 -type f -name '*.jar' -print -quit)
rm "$removed"
bash scripts/prepare-dbeaver-target.sh >"$temporary/removed.out"
python3 scripts/verify-dbeaver-tree.py "$archive" "$install" >/dev/null
rg -q 'replacing incomplete or unverified installation' "$temporary/removed.out"
echo 'negative guard passed: removed installed file repaired'

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

echo 'all Task 1 negative and reuse guards passed'
