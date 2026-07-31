#!/usr/bin/env bash
set -euo pipefail

required=(
  pom.xml .mvn/wrapper/maven-wrapper.properties mvnw mvnw.cmd .node-version .gitignore
  scripts/verify-layout.sh scripts/bootstrap-workspace.sh scripts/prepare-dbeaver-target.sh
  scripts/verify-dbeaver-baseline.sh scripts/verify-test-target.sh .github/workflows/ci.yml
  releng/baseline/dbeaver-ce-26.1.0-linux-x86_64.tar.gz.sha256
  releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.target/pom.xml
  releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.target/io.github.bakhtiiartashbolotov.dbeaver.monaco.target.target
  releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target/pom.xml
  releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target/io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target.target
  bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/pom.xml
  bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/META-INF/MANIFEST.MF
  bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/build.properties
  bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/pom.xml
  bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/META-INF/MANIFEST.MF
  bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/build.properties
  bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/pom.xml
  bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/META-INF/MANIFEST.MF
  bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/build.properties
  features/io.github.bakhtiiartashbolotov.dbeaver.monaco.feature/pom.xml
  features/io.github.bakhtiiartashbolotov.dbeaver.monaco.feature/feature.xml
  features/io.github.bakhtiiartashbolotov.dbeaver.monaco.feature/build.properties
  repository/pom.xml repository/category.xml
  tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/pom.xml
  tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/META-INF/MANIFEST.MF
  tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/build.properties
  tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/tests/ScaffoldTest.java
  tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/pom.xml
  tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/META-INF/MANIFEST.MF
  tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/build.properties
  tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/bridge/tests/ScaffoldTest.java
  tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/pom.xml
  tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/META-INF/MANIFEST.MF
  tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/build.properties
  tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/ScaffoldTest.java
  web/package.json web/package-lock.json web/pom.xml web/META-INF/MANIFEST.MF
  web/build.properties web/tsconfig.json web/src/main.ts docs/evidence/task-1-baseline.md
)

status=0
for path in "${required[@]}"; do
  if [[ ! -f "$path" ]]; then
    printf 'missing: %s\n' "$path"
    status=1
  fi
done

if rg -n --glob '!docs/**' --glob '!scripts/verify-layout.sh' \
  'dbeaver\.io/update|releases/latest|<dbeaver\.p2\.version>latest</dbeaver\.p2\.version>' \
  .; then
  printf '%s\n' 'forbidden unpinned DBeaver build input found' >&2
  status=1
fi

exit "$status"
