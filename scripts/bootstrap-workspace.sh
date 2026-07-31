#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 0 ]] || { echo 'bootstrap-workspace.sh accepts no arguments' >&2; exit 2; }
command -v unzip >/dev/null || { echo 'POSIX unzip is required' >&2; exit 1; }
[[ "$(java -version 2>&1 | sed -n '1s/.*version "\([0-9]*\).*/\1/p')" == 21 ]] || { echo 'Java 21 is required' >&2; exit 1; }
bash scripts/prepare-dbeaver-target.sh
bash scripts/verify-dbeaver-baseline.sh
if [[ -f .node-version ]]; then
 [[ "$(tr -d '\r\n' < .node-version)" == 24.18.1 && "$(node --version)" == v24.18.1 && "$(npm --version)" == 11.16.0 ]] || { echo 'Node/npm version mismatch' >&2; exit 1; }
fi
if [[ -x ./mvnw ]]; then
 ./mvnw --version | grep -q 'Apache Maven 3.9.16' || { echo 'Maven wrapper version mismatch' >&2; exit 1; }
 grep -q '^distributionSha256Sum=5af3b743dd8b876b5c45da33b676251e5f1687712644abb4ee519ca56e1d89ce$' .mvn/wrapper/maven-wrapper.properties || { echo 'wrapper checksum mismatch' >&2; exit 1; }
fi
echo 'workspace bootstrap passed'
