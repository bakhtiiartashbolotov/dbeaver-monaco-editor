#!/usr/bin/env bash
set -euo pipefail

repo=${1:-repository/target/repository}
production_target=${2:-releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.target/io.github.bakhtiiartashbolotov.dbeaver.monaco.target.target}
test_target=${3:-releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target/io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target.target}
[[ $# -le 3 ]] || { echo "usage: $0 [repository [production-target test-target]]" >&2; exit 2; }

python3 scripts/verify-target-definitions.py "$production_target" "$test_target"
python3 scripts/verify-p2-isolation.py "$repo"
echo 'test target and production repository isolation passed'
