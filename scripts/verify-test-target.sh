#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 1 ]] || { echo "usage: $0 <repository-directory>" >&2; exit 2; }
repo=$1; [[ -d "$repo" ]] || { echo "missing repository: $repo" >&2; exit 1; }
feature=features/io.github.bakhtiiartashbolotov.dbeaver.monaco.feature/feature.xml
! rg -n 'junit|org\.opentest4j|org\.apiguardian' "$feature"
mapfile -t manifests < <(find "$repo" -type f -name '*.jar' -print0 | xargs -0 -r -n1 sh -c 'unzip -p "$0" META-INF/MANIFEST.MF 2>/dev/null | sed -n "s/^Bundle-SymbolicName: *\([^;[:space:]]*\).*/\1/p"' | sort)
duplicates=$(printf '%s\n' "${manifests[@]}" | sed '/^$/d' | uniq -d)
[[ -z "$duplicates" ]] || { echo "duplicate symbolic names: $duplicates" >&2; exit 1; }
if find "$repo" -type f | rg 'junit|opentest4j|apiguardian'; then echo 'test-only bundle leaked into p2 repository' >&2; exit 1; fi
echo 'test target isolation passed'
