#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: $0 <repository-directory>" >&2; exit 2; }
repo=$1
plugins_dir=$repo/plugins
feature=features/io.github.bakhtiiartashbolotov.dbeaver.monaco.feature/feature.xml
[[ -d "$plugins_dir" ]] || { echo "missing repository plugins directory: $plugins_dir" >&2; exit 1; }

expected=(
  io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge
  io.github.bakhtiiartashbolotov.dbeaver.monaco.core
  io.github.bakhtiiartashbolotov.dbeaver.monaco.ui
  io.github.bakhtiiartashbolotov.dbeaver.monaco.web
)

read_bsn() {
  python3 - "$1" <<'PYCODE'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as bundle:
    manifest = bundle.read("META-INF/MANIFEST.MF").decode("utf-8")
logical_lines = []
for line in manifest.replace("\r\n", "\n").split("\n"):
    if line.startswith(" ") and logical_lines:
        logical_lines[-1] += line[1:]
    else:
        logical_lines.append(line)
values = [line.split(":", 1)[1].strip().split(";", 1)[0]
          for line in logical_lines if line.startswith("Bundle-SymbolicName:")]
if len(values) == 1:
    print(values[0])
PYCODE
}

mapfile -t jars < <(find "$plugins_dir" -maxdepth 1 -type f -name '*.jar' | sort)
[[ ${#jars[@]} -gt 0 ]] || { echo 'generated repository has no plugin JARs' >&2; exit 1; }
bsns=()
for jar in "${jars[@]}"; do
  bsn=$(read_bsn "$jar")
  [[ -n "$bsn" && $(printf '%s\n' "$bsn" | wc -l) -eq 1 ]] || {
    echo "plugin JAR has no single readable Bundle-SymbolicName: $jar" >&2
    exit 1
  }
  case "$bsn" in
    *.tests|*junit*|*surefire*|org.opentest4j|org.apiguardian.api)
      echo "test-only bundle leaked into p2 repository: $bsn" >&2
      exit 1
      ;;
  esac
  bsns+=("$bsn")
done
mapfile -t actual < <(printf '%s\n' "${bsns[@]}" | sort)
duplicates=$(printf '%s\n' "${actual[@]}" | uniq -d)
[[ -z "$duplicates" ]] || { echo "duplicate Bundle-SymbolicName values: $duplicates" >&2; exit 1; }
diff -u <(printf '%s\n' "${expected[@]}") <(printf '%s\n' "${actual[@]}")

mapfile -t feature_plugins < <(
  python3 - "$feature" <<'PY'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for plugin in root.findall("plugin"):
    print(plugin.attrib["id"])
PY
)
mapfile -t feature_plugins < <(printf '%s\n' "${feature_plugins[@]}" | sort)
diff -u <(printf '%s\n' "${expected[@]}") <(printf '%s\n' "${feature_plugins[@]}")

echo "production p2 Bundle-SymbolicName allowlist verified: ${actual[*]}"
echo 'test target isolation passed'
