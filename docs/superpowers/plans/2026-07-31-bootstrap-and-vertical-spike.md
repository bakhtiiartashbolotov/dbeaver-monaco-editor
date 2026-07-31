# DBeaver Monaco Editor Bootstrap and Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver an installable cross-platform DBeaver extension whose Monaco presentation safely edits the canonical DBeaver document and executes primary selected SQL through native DBeaver commands.

**Architecture:** Register an alternative `org.jkiss.dbeaver.sqlPresentation`. Keep a pure Java core for protocol/session/synchronization decisions and a thin DBeaver/SWT UI adapter. `IDocument` is canonical, Monaco is a projection, Eclipse owns undo, and incompatible behavior disables Monaco without damaging native DBeaver.

**Tech Stack:** Java 21, OSGi/Equinox, SWT/JFace, Maven 3.9.16 wrapper, Eclipse Tycho 5.0.3, checksum-pinned DBeaver CE 26.1.0 product target with 26.1.3 runtime verification, Node 24.18.1/npm 11.16.0, frontend-maven-plugin 2.0.2, strict TypeScript, Monaco 0.56.0, JSON Schema 2020-12, JUnit 5, jqwik, Vitest, Playwright, GitHub Actions.

## Global Constraints

- License is Apache-2.0; never copy GPL Equo code or assets.
- Minimum DBeaver is exactly 26.1.0. Build only against the official product
  archive whose SHA-256 is committed under `releng/baseline/`; never use
  `latest` or the nonexistent historical `update/ce/26.1.0` p2 URL.
- The exact Eclipse platform is the bundle set shipped in that archive. Do not
  add an independent Eclipse p2 repository to the minimum target.
- Verification target is DBeaver 26.1.3 in addition to the minimum.
- Task 10 creates the checksum pins and jobs for 26.1.3. Earlier tasks verify
  only the targets explicitly introduced by their own file lists and steps.
- Java source and bytecode target is exactly 21.
- Maven is exactly 3.9.16. Node/npm are exactly 24.18.1/11.16.0 and remain
  build-time only.
- Runtime uses the system SWT Browser; Chromium, Electron, runtime Node, CDN, and external web requests are forbidden.
- `IDocument` is canonical; Monaco is a projection; Eclipse undo is authoritative.
- DBeaver owns save, SQL execution, connections, transactions, and result UI.
- Core production Java imports no DBeaver, Eclipse, SWT, OSGi service, Gson, or Jackson implementation API.
- Java↔TypeScript offsets are UTF-16 code units.
- Every document change validates readiness epoch, base revision, document
  stamp, sequence, size, and edit-count bounds.
- Commands first freeze/drain the Browser, then validate readiness epoch,
  document revision/stamp, acknowledged edit sequence, and acknowledged
  semantic-selection sequence. The SWT thread never waits for JavaScript.
- Missing critical capability disables Monaco only; native DBeaver must remain usable.
- Snapshot and mutation/compound-undo readiness never enable editing by
  themselves. `READY` additionally requires a proven native command channel
  and scoped command guard.
- The one automatic resync allowance is consumed for the SQL-editor
  lifetime and cannot reset after success. No resync snapshot may overwrite a
  live projection until its correlated bounded recovery candidate is
  successfully stored.
- Tycho `eclipse-test-plugin` focused commands terminate in `verify`, not
  Maven `test`.
- GitHub Actions use explicit runner labels and full-commit-SHA action pins;
  floating `*-latest` runner labels and floating action tags are forbidden.
- One numbered task is one cloud run, branch, review gate, and pull request.
- Stop after each task; do not execute the next task automatically.
- From Task 2 onward, every fresh checkout/cloud run executes
  `bash scripts/bootstrap-workspace.sh` before its first Maven command. The
  focused command blocks below assume that idempotent prerequisite has passed;
  ignored `.cache/` state is never assumed to survive between sessions.

---

## Planned file map

```text
pom.xml
.mvn/wrapper/maven-wrapper.properties
mvnw
mvnw.cmd
.gitignore
.github/workflows/ci.yml
.github/workflows/compatibility.yml
.github/workflows/canary.yml
.github/workflows/performance.yml
.github/workflows/release.yml
.github/dependabot.yml
scripts/verify-layout.sh

bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/
  pom.xml
  META-INF/MANIFEST.MF
  build.properties
  src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/
    capability/
    command/
    recovery/
    session/
    sync/

bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/
  pom.xml
  META-INF/MANIFEST.MF
  build.properties
  src/io/github/bakhtiiartashbolotov/dbeaver/monaco/bridge/
    mapping/
    validation/
    wire/

third-party/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge-json-runtime/
  pom.xml

bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/
  pom.xml
  META-INF/MANIFEST.MF
  build.properties
  plugin.xml
  src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/
    browser/
    command/
    compatibility/
    lifecycle/
    presentation/
    selection/
    sync/

protocol/
  schema/editor-bridge.schema.json
  fixtures/valid/
  fixtures/invalid/

web/
  pom.xml
  META-INF/MANIFEST.MF
  build.properties
  package.json
  package-lock.json
  tsconfig.json
  vite.config.ts
  vitest.config.ts
  playwright.config.ts
  index.html
  src/
    bridge/
    editor/
    generated/
    main.ts
  tests/

releng/
  baseline/dbeaver-ce-26.1.0-linux-x86_64.tar.gz.sha256
  io.github.bakhtiiartashbolotov.dbeaver.monaco.target/
    pom.xml
    io.github.bakhtiiartashbolotov.dbeaver.monaco.target.target
  io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target/
    pom.xml
    io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target.target
  io.github.bakhtiiartashbolotov.dbeaver.monaco.native.test.target/
    pom.xml
    io.github.bakhtiiartashbolotov.dbeaver.monaco.native.test.target.target

features/io.github.bakhtiiartashbolotov.dbeaver.monaco.feature/
  pom.xml
  feature.xml
  build.properties

features/io.github.bakhtiiartashbolotov.dbeaver.monaco.source.feature/
  pom.xml
  feature.xml
  build.properties

repository/
  pom.xml
  category.xml

tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/
tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/
tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/
tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.e2e.tests/
docs/evidence/
docs/compatibility.md
```

Files change together by task below. Do not pre-create later-task production
classes merely to make the tree look complete.

### Task 1: Reproducible Tycho and npm scaffold

**Files:**

- Create: `pom.xml`
- Create: `.mvn/wrapper/maven-wrapper.properties`
- Create: `mvnw`
- Create: `mvnw.cmd`
- Create: `.node-version`
- Create: `.gitignore`
- Create: `scripts/verify-layout.sh`
- Create: `scripts/bootstrap-workspace.sh`
- Create: `scripts/prepare-dbeaver-target.sh`
- Create: `scripts/verify-dbeaver-baseline.sh`
- Create: `scripts/verify-test-target.sh`
- Create: `.github/workflows/ci.yml`
- Create: `releng/baseline/dbeaver-ce-26.1.0-linux-x86_64.tar.gz.sha256`
- Create: `releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.target/pom.xml`
- Create: `releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.target/io.github.bakhtiiartashbolotov.dbeaver.monaco.target.target`
- Create: `releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target/pom.xml`
- Create: `releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target/io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target.target`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/pom.xml`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/META-INF/MANIFEST.MF`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/build.properties`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/pom.xml`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/META-INF/MANIFEST.MF`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/build.properties`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/pom.xml`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/META-INF/MANIFEST.MF`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/build.properties`
- Create: `features/io.github.bakhtiiartashbolotov.dbeaver.monaco.feature/pom.xml`
- Create: `features/io.github.bakhtiiartashbolotov.dbeaver.monaco.feature/feature.xml`
- Create: `features/io.github.bakhtiiartashbolotov.dbeaver.monaco.feature/build.properties`
- Create: `repository/pom.xml`
- Create: `repository/category.xml`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/pom.xml`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/META-INF/MANIFEST.MF`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/build.properties`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/tests/ScaffoldTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/pom.xml`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/META-INF/MANIFEST.MF`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/build.properties`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/bridge/tests/ScaffoldTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/pom.xml`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/META-INF/MANIFEST.MF`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/build.properties`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/ScaffoldTest.java`
- Create: `web/package.json`
- Create: `web/package-lock.json`
- Create: `web/pom.xml`
- Create: `web/META-INF/MANIFEST.MF`
- Create: `web/build.properties`
- Create: `web/tsconfig.json`
- Create: `web/src/main.ts`
- Create: `docs/evidence/task-1-baseline.md`

**Interfaces:**

- Consumes: the official
  `https://dbeaver.io/files/26.1.0/dbeaver-ce-26.1.0-linux-x86_64.tar.gz`
  archive and its official SHA-256 only.
- Produces: a checksum-locked local DBeaver installation target; a separate
  test-only target overlay; stable Maven module paths; `tycho.version=5.0.3`;
  Maven 3.9.16; Java release 21; Node/npm 24.18.1/11.16.0; and the standard
  bootstrap/verification commands used by every later task.

- [ ] **Step 1: Write the failing repository-layout check**

Create `scripts/verify-layout.sh` with `set -euo pipefail` and an array
containing every Task 1 file above. For each path, print `missing: <path>` and
exit non-zero when absent. Reject `dbeaver.io/update`, `releases/latest`, and
`<dbeaver.p2.version>latest</dbeaver.p2.version>` anywhere in build inputs.

- [ ] **Step 2: Run the layout check and observe failure**

Run:

```bash
bash scripts/verify-layout.sh
```

Expected: non-zero exit with at least `missing: pom.xml`.

- [ ] **Step 3: Capture and lock the official DBeaver baseline**

Download the archive from the exact versioned DBeaver URL and its checksum
from the exact official checksum URL:

```text
https://dbeaver.io/files/26.1.0/dbeaver-ce-26.1.0-linux-x86_64.tar.gz
https://downloads.dbeaver.net/community/26.1.0/checksum/dbeaver-ce-26.1.0-linux-x86_64.tar.gz.sha256
```

Do not construct the checksum URL under `dbeaver.io/files`; that path returns
404 for this artifact. Confirm that the downloaded checksum file contains
exactly one lowercase 64-hex digest, verify the archive, and commit only that
digest as:

```bash
releng/baseline/dbeaver-ce-26.1.0-linux-x86_64.tar.gz.sha256
```

Implement `scripts/prepare-dbeaver-target.sh` to:

1. require the committed digest before any download;
2. download only the exact 26.1.0 archive into `.cache/downloads`, following
   HTTPS redirects only; the currently expected final host is
   `release-assets.githubusercontent.com`;
3. calculate SHA-256 with `sha256sum` or `shasum -a 256`;
4. stop before extraction on mismatch;
5. extract atomically into `.cache/dbeaver-26.1.0/dbeaver`;
6. never accept a checksum supplied by a caller or a `latest` URL.

If the official versioned URL redirects to a different scheme or an
unallowlisted host, stop and record the effective redirect chain instead of
silently expanding network access. The committed digest remains authoritative
even for an allowlisted redirect.

Add `.cache/` to `.gitignore`. Run the script twice; the second run must reuse
the already verified archive without mutating the installation.

Create `scripts/bootstrap-workspace.sh` as the single idempotent entry point
for every later fresh session. It calls the preparation and baseline checks,
requires Java 21 and POSIX `unzip`, validates `.node-version` plus Node/npm
24.18.1/11.16.0 when those files exist, validates the Maven 3.9.16 wrapper
after Task 1 creates it, and exits before Maven on any mismatch. It accepts no
URL, digest, or product override.

- [ ] **Step 4: Verify the shipped API/platform baseline**

Implement `scripts/verify-dbeaver-baseline.sh` to fail unless the installation
contains the SQL editor bundle, `SQLEditorPresentation.class`,
`org.jkiss.dbeaver.sqlPresentation` schema, JFace `IDocumentExtension4`, SWT
Browser, and the Equinox launcher. It must unambiguously extract the DBeaver
application ID and product ID from the prepared product's own
Equinox/product metadata and fail when either is missing or multiple values
could match. It must reject any bundle path outside the prepared installation.

Write `docs/evidence/task-1-baseline.md` with the archive URL and SHA-256,
actual DBeaver product version, Eclipse/Equinox/SWT bundle versions, exported
SQL editor package, and the exact public presentation, command, selection,
undo, and presentation-switch APIs found. At minimum, compile-contract
`SQLEditorPresentation`, both public `SQLEditor.showExtraPresentation`
overloads, `SQLEditorCommands` statement/script IDs, the exact public
save/undo/redo command IDs and services, `ISelectionProvider`,
`IDocumentExtension4`, and compound undo. Enumerate the actual toolbar, menu,
and global-keybinding contributions for save, undo, redo, statement, and
script; prove each surface resolves through the recorded command ID rather
than directly mutating the editor. Missing or ambiguous evidence for any of
those five critical routes blocks Task 7.

Also record every native SQL-format action and surface found. If it is backed
by a public command, capture its exact ID, handler service, enabled-state
contract, and toolbar/menu/keybinding mappings. If no format surface exists,
record that explicit optional absence. A mutating format surface that is not
publicly command-backed is a fail-closed compatibility finding, because Task 7
cannot safely guard it while Monaco is active. Read the prepared product's own
Equinox/product metadata and record the exact DBeaver application ID, product
ID, launcher path, and any required UI-test application arguments; Task 4 must
consume these captured values rather than guess them. This is generated
evidence, not copied DBeaver implementation source.

- [ ] **Step 5: Generate the Maven 3.9.16 wrapper**

First download the exact Apache Maven 3.9.16 binary ZIP and its official
SHA-512 sidecar:

```text
https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.16/apache-maven-3.9.16-bin.zip
https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.16/apache-maven-3.9.16-bin.zip.sha512
```

Verify the ZIP against the sidecar, calculate its lowercase SHA-256, and then
run with an installed Maven:

```bash
mvn -N org.apache.maven.plugins:maven-wrapper-plugin:3.3.4:wrapper \
  -Dmaven=3.9.16 -Dtype=only-script \
  -DdistributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.16/apache-maven-3.9.16-bin.zip \
  -DdistributionSha256Sum=<verified-maven-zip-sha256>
```

Expected: executable `mvnw`, Windows `mvnw.cmd`, and wrapper properties pinned
to the exact Maven Central `apache-maven-3.9.16-bin.zip` URL and its verified
`distributionSha256Sum`. On POSIX, `scripts/bootstrap-workspace.sh` requires
`unzip` before invoking the wrapper. The lite wrapper may otherwise fall back
from ZIP to `tar.gz` while retaining the ZIP checksum, which is not a valid
reproducible path. Commit wrapper metadata; `only-script` means no wrapper jar
or downloaded Maven binary is committed.

- [ ] **Step 6: Create the local-installation target and Tycho reactor**

The target definition has one `Directory` location:

```xml
<location
    path="${project_loc:io.github.bakhtiiartashbolotov.dbeaver.monaco.target}/../../.cache/dbeaver-26.1.0/dbeaver"
    type="Directory"/>
```

Configure `target-platform-configuration` to consume the
`eclipse-target-definition` artifact. Use Maven's CI-friendly `${revision}` as
the root and child project version so a protected release can override it
without editing tracked POMs. Do not declare any p2 repository in the release
build. Use this root property/module shape:

```xml
<properties>
  <revision>0.1.0-SNAPSHOT</revision>
  <tycho.version>5.0.3</tycho.version>
  <maven.compiler.release>21</maven.compiler.release>
  <dbeaver.baseline.version>26.1.0</dbeaver.baseline.version>
</properties>
<modules>
  <module>releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.target</module>
  <module>releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target</module>
  <module>bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core</module>
  <module>bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge</module>
  <module>web</module>
  <module>bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui</module>
  <module>features/io.github.bakhtiiartashbolotov.dbeaver.monaco.feature</module>
  <module>repository</module>
  <module>tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests</module>
  <module>tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests</module>
  <module>tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests</module>
</modules>
```

Configure `tycho-maven-plugin`, `target-platform-configuration`,
`tycho-compiler-plugin`, `tycho-packaging-plugin`, and target-platform
validation at 5.0.3. Compile the platform-neutral plugin against the exact
Linux product installation. Native Windows/macOS Browser and installation
behavior is exercised later against their checksum-pinned complete products,
not by adding their platform fragments to this compile target.

Use `eclipse-plugin`, `eclipse-feature`, and `eclipse-repository` packaging as
appropriate. The target module uses `eclipse-target-definition`. Test modules
use `eclipse-test-plugin` and contain one JUnit 5 smoke test each. Empty
runtime bundles contain metadata only. The UI manifest requires the public SQL
editor bundle to prove baseline resolution but contains no production Java.
Use a bounded semantic bundle/package range anchored to the base version
observed in Step 4, not an exact qualifier or product-string equality. Runtime
capability probes remain authoritative. The bridge and web bundles contain no
DBeaver dependency.
From this scaffold onward, the runtime feature lists exactly core, bridge, web,
and UI bundles so every later p2 build exercises their install-time
resolution; Task 10 adds sources/signing/release metadata, not a previously
untested dependency graph.

The production target remains the single DBeaver `Directory` location above.
Create a distinct test target that repeats that exact verified `Directory`
location and adds one `type="Maven"` location with
`includeDependencyDepth="infinite"`, `includeDependencyScopes="compile"`,
`includeSource="false"`, and `missingManifest="error"`. Its exact roots are:

```text
org.junit.jupiter:junit-jupiter-api:5.13.4
org.junit.jupiter:junit-jupiter-engine:5.13.4
org.junit.platform:junit-platform-launcher:1.13.4
```

Every test module overrides `target-platform-configuration` to use only this
test target. Production bundles, features, and repository continue to use only
the production target. The scaffold PDE tests assert the resolved Jupiter
API/engine 5.13.4 and Platform 1.13.4 at runtime.
`scripts/verify-test-target.sh <repository-directory>` fails on generated
manifests or duplicate symbolic names and proves no test-only bundle appears
in the runtime feature or generated p2 repository.

- [ ] **Step 7: Create the minimal locked Node workspace**

Write `24.18.1` to `.node-version`. Set `engines.node` to `24.18.1` and
`packageManager` to `npm@11.16.0`. Add scripts:

```json
{
  "scripts": {
    "lint": "tsc --noEmit",
    "test": "node --test",
    "build": "tsc --noEmit"
  }
}
```

Install TypeScript 6.0.3 as an exact development dependency and commit the
generated lockfile:

```bash
npm --prefix web install --save-dev --save-exact typescript@6.0.3
```

`web/src/main.ts` must export `const WEB_BOOTSTRAP = "not-started"` so the
build proves TypeScript resolution without implementing Monaco.

- [ ] **Step 8: Run the scaffold checks**

Run:

```bash
bash scripts/verify-layout.sh
bash scripts/bootstrap-workspace.sh
./mvnw -B verify
bash scripts/verify-test-target.sh repository/target/repository
npm --prefix web ci
npm --prefix web run lint
npm --prefix web test
npm --prefix web run build
```

Expected: every command exits zero; production resolves only the
checksum-pinned DBeaver 26.1.0 installation, while test modules add only the
exact Maven Central test bundles declared in the test target.

- [ ] **Step 9: Add the smoke CI workflow**

Create `.github/workflows/ci.yml` for pull requests and pushes to `main` on
`ubuntu-24.04`. Set workflow-level `permissions: { contents: read }`; do not
use `pull_request_target`, pass secrets to pull-request jobs, or grant write
permission. Pin every third-party action to a full commit SHA with its release
tag in a comment, and configure checkout with `persist-credentials: false`.
Use Temurin Java 21, `.node-version`, npm 11.16.0, and Maven/npm caches. Run
the exact commands from Step 8. Cache only the verified DBeaver archive by the
committed digest, never an unverified extracted directory. Upload the
generated p2 repository and baseline evidence as artifacts.

- [ ] **Step 10: Commit the independently reviewable scaffold**

```bash
git add .mvn mvnw mvnw.cmd pom.xml .gitignore scripts .github/workflows/ci.yml \
  .node-version releng bundles features repository tests web docs/evidence
git commit -m "build: add reproducible DBeaver plugin scaffold"
```

Stop and open the Task 1 draft PR. Do not begin protocol or Monaco code.

### Task 2: Typed protocol and pure-core session state machine

**Files:**

- Create: `protocol/schema/editor-bridge.schema.json`
- Create: `protocol/fixtures/valid/handshake-request.json`
- Create: `protocol/fixtures/valid/handshake-response.json`
- Create: `protocol/fixtures/valid/session-mode.json`
- Create: `protocol/fixtures/valid/document-snapshot.json`
- Create: `protocol/fixtures/valid/snapshot-ack.json`
- Create: `protocol/fixtures/valid/edit-batch.json`
- Create: `protocol/fixtures/valid/document-patch.json`
- Create: `protocol/fixtures/valid/patch-ack.json`
- Create: `protocol/fixtures/valid/document-ack.json`
- Create: `protocol/fixtures/valid/selection-update.json`
- Create: `protocol/fixtures/valid/selection-ack.json`
- Create: `protocol/fixtures/valid/flush-request.json`
- Create: `protocol/fixtures/valid/flush-response.json`
- Create: `protocol/fixtures/valid/command-request.json`
- Create: `protocol/fixtures/valid/command-response.json`
- Create: `protocol/fixtures/valid/recovery-export-request.json`
- Create: `protocol/fixtures/valid/recovery-export-response.json`
- Create: `protocol/fixtures/valid/failure.json`
- Create: `protocol/fixtures/valid/safe-integer-max.json`
- Create: `protocol/fixtures/invalid/unknown-command.json`
- Create: `protocol/fixtures/invalid/missing-session.json`
- Create: `protocol/fixtures/invalid/missing-document-stamp.json`
- Create: `protocol/fixtures/invalid/missing-readiness-epoch.json`
- Create: `protocol/fixtures/invalid/missing-recovery-eligibility.json`
- Create: `protocol/fixtures/invalid/unknown-envelope-property.json`
- Create: `protocol/fixtures/invalid/wrong-protocol-major.json`
- Create: `protocol/fixtures/invalid/wrong-protocol-minor.json`
- Create: `protocol/fixtures/invalid/unsafe-integer.json`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/session/SessionState.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/session/SessionContext.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/session/SessionEvent.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/session/SessionEffect.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/session/SessionTransition.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/session/ReadinessStamp.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/session/DocumentReadiness.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/session/CommandGuardLease.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/session/ResyncTransaction.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/session/CircuitBreaker.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/session/EditorSessionMachine.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/capability/Capability.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/capability/CapabilityCriticality.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/capability/CapabilityReport.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/capability/FailureCode.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/protocol/ProtocolLimits.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/recovery/RecoveryLimits.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/recovery/RecoveryCandidate.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/recovery/RecoveryCandidateHandle.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/recovery/RecoveryExportRequest.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/recovery/RecoveryExportResponse.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/DocumentSnapshot.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/SnapshotAck.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/TextEdit.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/EditBatch.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/DocumentAck.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/CanonicalPatch.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/CanonicalPatchAck.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/ApplyResult.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/PrimarySelection.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/SelectionAck.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/command/RevisionBarrier.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/command/SessionMode.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/command/FlushBarrierRequest.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/command/FlushBarrierResponse.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/command/EditorCommandRequest.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/command/EditorCommandResponse.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/command/CommandReplayLedger.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/command/ReplayDecision.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/command/CommandCompletionPermit.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/command/ExecuteRequest.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/command/EditorCommand.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/command/CommandOrigin.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/command/CommandResult.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/bridge/wire/WireEnvelope.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/bridge/mapping/BridgeMessageMapper.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/bridge/validation/BridgeMessageDecoder.java`
- Create: `third-party/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge-json-runtime/pom.xml`
- Create: `scripts/verify-bridge-closure.sh`
- Create: `web/src/generated/editor-bridge.d.ts`
- Create: `web/src/generated/validate-editor-bridge.mjs`
- Create: `web/src/generated/validate-editor-bridge.d.mts`
- Create: `web/src/bridge/validateEnvelope.ts`
- Create: `web/scripts/generate-protocol.mjs`
- Create: `web/scripts/verify-generated-protocol.mjs`
- Create: `web/tests/protocolFixtures.test.ts`
- Create: `web/tests/protocolTypes.contract.ts`
- Create: `web/tsconfig.protocol-contract.json`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/tests/EditorSessionMachineTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/tests/ArchitectureBoundaryTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/bridge/tests/BridgeSchemaContractTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/bridge/tests/BridgeMessageMapperTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/bridge/tests/InstalledBundleValidationTest.java`
- Modify: `pom.xml`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/pom.xml`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/pom.xml`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/META-INF/MANIFEST.MF`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/build.properties`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/pom.xml`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/META-INF/MANIFEST.MF`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/pom.xml`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests/META-INF/MANIFEST.MF`
- Modify: `web/package.json`
- Modify: `web/package-lock.json`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**

- Consumes: Task 1 module paths and verification commands.
- Produces:

```java
public enum SessionState {
    NEW, PROBING, LOADING, HANDSHAKING, SYNCING, READY,
    RESYNCING, DEGRADED, FAILED, DISPOSED
}

public record SessionContext(
    SessionState state,
    CapabilityReport capabilities,
    long readinessEpoch,
    Optional<SnapshotAck> pendingSnapshotAcknowledgement,
    Optional<ReadinessStamp> pendingRecoveryCheckpoint,
    Optional<DocumentReadiness> currentDocument,
    OptionalLong mutationProofEpoch,
    Optional<CommandGuardLease> commandGuardLease,
    Optional<ResyncTransaction> resyncTransaction,
    CircuitBreaker circuitBreaker) {
    public boolean documentReady() {
        return currentDocument
            .filter(DocumentReadiness::recoveryEligible)
            .map(DocumentReadiness::stamp)
            .filter(stamp -> stamp.readinessEpoch() == readinessEpoch)
            .isPresent();
    }
    public boolean mutationReady() {
        return mutationProofEpoch.isPresent()
            && mutationProofEpoch.getAsLong() == readinessEpoch;
    }
    public boolean commandReady() {
        return commandGuardLease
            .filter(lease -> lease.readinessEpoch() == readinessEpoch)
            .isPresent();
    }
}

public record ReadinessStamp(long readinessEpoch, long revision,
                             long documentStamp) {}
public record DocumentReadiness(ReadinessStamp stamp,
                                long acknowledgedEditSequence,
                                boolean recoveryEligible) {}
public record CommandGuardLease(long readinessEpoch, UUID leaseId) {}
public sealed interface ResyncTransaction {
    UUID resyncId();
    ReadinessStamp sourceStamp();

    record CapturingRecovery(
        UUID resyncId,
        ReadinessStamp sourceStamp,
        long recoverySequence,
        UUID recoveryRequestId) implements ResyncTransaction {}

    record PreparingSnapshot(
        UUID resyncId,
        ReadinessStamp sourceStamp,
        long targetReadinessEpoch,
        RecoveryCandidateHandle recoveryHandle,
        UUID snapshotCaptureId) implements ResyncTransaction {}
}

public sealed interface SessionEvent permits ProbeStarted, ProbePassed, ProbeFailed,
    ProbeCompleted, PageLoaded, HandshakeAccepted, SnapshotAcknowledged,
    RecoveryCheckpointReady, DocumentReadinessAdvanced, RecoveryHeadroomLost,
    MutationChannelReady, CommandChannelReady, CommandChannelLost,
    OptionalCapabilityLost, OptionalCapabilityRecovered, RevisionMismatch,
    ResyncRecoveryStored, ResyncRecoveryCaptureFailed,
    ResyncSnapshotPrepared, ResyncSnapshotPreparationFailed,
    BridgeFailed, DisposeRequested {}

public record SnapshotAcknowledged(SnapshotAck acknowledgement)
    implements SessionEvent {}
public record RecoveryCheckpointReady(ReadinessStamp stamp)
    implements SessionEvent {}
public record DocumentReadinessAdvanced(ReadinessStamp stamp,
                                        long acknowledgedEditSequence,
                                        boolean recoveryEligible)
    implements SessionEvent {}
public record RecoveryHeadroomLost(ReadinessStamp stamp)
    implements SessionEvent {}
public record MutationChannelReady(long readinessEpoch)
    implements SessionEvent {}
public record CommandChannelReady(long readinessEpoch, UUID guardLeaseId)
    implements SessionEvent {}
public record CommandChannelLost(long readinessEpoch, UUID guardLeaseId)
    implements SessionEvent {}
public record RevisionMismatch(
    UUID resyncId,
    ReadinessStamp sourceStamp,
    long recoverySequence,
    UUID recoveryRequestId) implements SessionEvent {}
public record ResyncRecoveryStored(
    UUID resyncId,
    long sourceReadinessEpoch,
    long recoverySequence,
    UUID recoveryRequestId,
    RecoveryCandidateHandle handle,
    UUID snapshotCaptureId)
    implements SessionEvent {}
public record ResyncRecoveryCaptureFailed(
    UUID resyncId,
    long sourceReadinessEpoch,
    long recoverySequence,
    UUID recoveryRequestId,
    FailureCode code)
    implements SessionEvent {}
public record ResyncSnapshotPrepared(
    UUID resyncId,
    UUID snapshotCaptureId,
    long targetReadinessEpoch,
    RecoveryCandidateHandle recoveryHandle,
    DocumentSnapshot snapshot)
    implements SessionEvent {}
public record ResyncSnapshotPreparationFailed(
    UUID resyncId,
    UUID snapshotCaptureId,
    long targetReadinessEpoch,
    RecoveryCandidateHandle recoveryHandle,
    FailureCode code)
    implements SessionEvent {}

public record SessionTransition(
    SessionContext context,
    List<SessionEffect> effects) {}

public final class EditorSessionMachine {
    public SessionTransition apply(SessionContext current, SessionEvent event);
}

public record DocumentSnapshot(long readinessEpoch, String text,
                               long revision, long documentStamp,
                               long resetEditSequence,
                               long resetSelectionSequence) {}
public record SnapshotAck(long readinessEpoch, long revision,
                          long documentStamp, long resetEditSequence,
                          long resetSelectionSequence) {}
public record TextEdit(int offset, int length, String text) {}
public record EditBatch(long readinessEpoch, long baseRevision,
                        long baseDocumentStamp,
                        long clientSequence,
                        List<TextEdit> edits) {}
public record DocumentAck(long readinessEpoch, long revision,
                          long documentStamp,
                          long clientSequence,
                          boolean recoveryEligible) {}
public record CanonicalPatch(long readinessEpoch, long baseRevision,
                             long baseDocumentStamp,
                             long revision, long documentStamp,
                             List<TextEdit> edits) {}
public record CanonicalPatchAck(long readinessEpoch, long revision,
                                long documentStamp) {}
public record PrimarySelection(int offset, int length, long readinessEpoch,
                               long revision,
                               long documentStamp, long selectionSequence) {}
public record SelectionAck(long readinessEpoch, long revision,
                           long documentStamp,
                           long selectionSequence) {}
public sealed interface ApplyResult {
    record Applied(DocumentAck acknowledgement) implements ApplyResult {}
    record Rejected(FailureCode code) implements ApplyResult {}
}
public record RevisionBarrier(long readinessEpoch, long revision,
                              long documentStamp, long editSequence,
                              long selectionSequence) {}
public enum EditMode { READ_ONLY, EDITABLE, FAILED }
public record SessionMode(long readinessEpoch, EditMode mode,
                          Optional<FailureCode> reason) {}
public record FlushBarrierRequest(long readinessEpoch, long flushSequence,
                                  UUID barrierId) {}
public record FlushBarrierResponse(
    long readinessEpoch,
    long flushSequence,
    UUID barrierId,
    RevisionBarrier acknowledgedBarrier,
    long latestDispatchedEditSequence,
    long latestDispatchedSelectionSequence) {}
public record ExecuteRequest(ExecutionMode mode,
                             OptionalLong requestedSelectionSequence) {
    public enum ExecutionMode { STATEMENT, SCRIPT }
}
public sealed interface EditorCommand {
    record Save() implements EditorCommand {}
    record Undo() implements EditorCommand {}
    record Redo() implements EditorCommand {}
    record Format() implements EditorCommand {}
    record Execute(ExecuteRequest request) implements EditorCommand {}
}
public enum CommandOrigin { WEB, NATIVE }
public record EditorCommandRequest(
    CommandOrigin origin,
    long readinessEpoch,
    long commandSequence,
    UUID messageId,
    EditorCommand command) {}
public record EditorCommandResponse(
    long readinessEpoch,
    long commandSequence,
    UUID requestMessageId,
    Optional<RevisionBarrier> appliedBarrier,
    CommandResult result) {}
public sealed interface CommandResult {
    record Accepted() implements CommandResult {}
    record Rejected(FailureCode code) implements CommandResult {}
}

public final class CommandReplayLedger {
    public static final int MAX_COMPLETED_ENTRIES = 256;
    public ReplayDecision accept(EditorCommandRequest request);
    public void complete(CommandCompletionPermit permit,
                         EditorCommandRequest request,
                         EditorCommandResponse response);
}
public sealed interface ReplayDecision {
    record Start(CommandCompletionPermit permit)
        implements ReplayDecision {}
    record Cached(EditorCommandResponse response)
        implements ReplayDecision {}
    record Rejected(FailureCode code)
        implements ReplayDecision {}
}
public record CommandCompletionPermit(UUID id) {}

public enum FailureCode {
    INVALID_TRANSITION,
    PROTOCOL_MISMATCH,
    SCHEMA_INVALID,
    UNKNOWN_MESSAGE_KIND,
    UNKNOWN_COMMAND,
    STALE_SESSION,
    STALE_READINESS_EPOCH,
    READINESS_EPOCH_EXHAUSTED,
    INVALID_ORIGIN,
    PAYLOAD_TOO_LARGE,
    DOCUMENT_TOO_LARGE,
    SESSION_NOT_READY,
    CAPABILITY_MISSING,
    INCOMPATIBLE_DBEAVER_API,
    BROWSER_UNAVAILABLE,
    BRIDGE_UNAVAILABLE,
    WORKER_UNAVAILABLE,
    ASSET_INTEGRITY_FAILED,
    MUTATION_PROBE_FAILED,
    COMPOUND_UNDO_UNAVAILABLE,
    COMMAND_UNAVAILABLE,
    COMMAND_DISABLED,
    COMMAND_GUARD_UNAVAILABLE,
    STALE_REVISION,
    STALE_DOCUMENT_STAMP,
    STALE_SELECTION,
    NON_MONOTONIC_SEQUENCE,
    INVALID_RANGE,
    OVERLAPPING_EDITS,
    SURROGATE_BOUNDARY,
    DOCUMENT_CHANGED_DURING_APPLY,
    DOCUMENT_APPLY_FAILED,
    CANONICAL_ROLLBACK_FAILED,
    RESYNC_REQUIRED,
    RESYNC_LIMIT_EXCEEDED,
    RECOVERY_CAPACITY_EXCEEDED,
    RECOVERY_EXPORT_UNAVAILABLE,
    RECOVERY_EXPORT_TOO_LARGE,
    PRESENTATION_SWITCH_REJECTED,
    FLUSH_BARRIER_FAILED,
    SWITCH_BARRIER_FAILED,
    OPERATION_TIMEOUT,
    DISPOSED
}

public final class ProtocolLimits {
    public static final long MAX_BRIDGE_MESSAGE_UTF8_BYTES = 64L * 1024 * 1024;
    public static final long MAX_EDIT_BATCH_UTF8_BYTES = 8L * 1024 * 1024;
    public static final int MAX_EDITS_PER_BATCH = 1_024;
    public static final int MAX_TEXT_UTF16_CODE_UNITS = 10 * 1024 * 1024;
}

public record RecoveryCandidate(
    Source source,
    long recoverySequence,
    UUID requestId,
    long readinessEpoch,
    long revision,
    long documentStamp,
    long latestDispatchedEditSequence,
    long latestAcknowledgedEditSequence,
    long latestDispatchedSelectionSequence,
    long latestAcknowledgedSelectionSequence,
    String text) {
    public enum Source { LIVE_BROWSER_EXPORT, HOST_JOURNAL }
}
public record RecoveryCandidateHandle(UUID id) {}
public record RecoveryExportRequest(long readinessEpoch,
                                    long recoverySequence,
                                    UUID requestId) {}
public record RecoveryExportResponse(
    long readinessEpoch,
    long recoverySequence,
    UUID requestId,
    long revision,
    long documentStamp,
    long latestDispatchedEditSequence,
    long latestAcknowledgedEditSequence,
    long latestDispatchedSelectionSequence,
    long latestAcknowledgedSelectionSequence,
    String text) {}

public record RecoveryLimits(int maxEntries, long maxJournalWireBytes) {
    public static final long MAX_JOURNAL_ENTRY_METADATA_UTF8_BYTES =
        64L * 1024;
    public static final RecoveryLimits DEFAULT =
        new RecoveryLimits(2_048, 32L * 1024 * 1024);
}
```

`resyncTransaction` is present if and only if state is `RESYNCING`, and its
sealed variant is the authorization phase. No boolean combination or inferred
effect ordering may substitute for that invariant.

- [ ] **Step 1: Write failing state-transition and boundary tests**

Test at minimum:

```java
assertEquals(SessionState.PROBING,
    machine.apply(newContext(SessionState.NEW), new ProbeStarted())
        .context().state());
assertEquals(SessionState.SYNCING,
    machine.apply(newContext(SessionState.SYNCING),
        new SnapshotAcknowledged(new SnapshotAck(1, 1, 7, 0, 0)))
        .context().state());
assertEquals(SessionState.SYNCING,
    machine.apply(newContext(SessionState.SYNCING),
        new RecoveryCheckpointReady(new ReadinessStamp(1, 1, 7)))
        .context().state());
assertEquals(SessionState.SYNCING,
    machine.apply(newContext(SessionState.SYNCING),
        new MutationChannelReady(1)).context().state());
assertEquals(SessionState.READY,
    machine.apply(contextWithQualifiedSnapshotAndMutationReady(),
        new CommandChannelReady(1, UUID.fromString(
            "00000000-0000-0000-0000-000000000001")))
        .context().state());
assertEquals(SessionState.FAILED,
    machine.apply(newContext(SessionState.HANDSHAKING),
        criticalFailure(FailureCode.PROTOCOL_MISMATCH)).context().state());
```

Also prove that `SnapshotAcknowledged`, `RecoveryCheckpointReady`, and
`MutationChannelReady` cannot independently emit `EnableEditing`; the four
signals that form the three readiness facts enable exactly once in every
order; mismatched epoch/revision/stamp evidence never combines; duplicate
readiness events are idempotent; and current `RecoveryHeadroomLost` revokes
editability with `RECOVERY_CAPACITY_EXCEEDED`. Optional-only failures select
`DEGRADED` only after all three critical readiness facts exist.

After `READY`, apply several `DocumentReadinessAdvanced` events with increasing
revision/stamp values and prove the reducer atomically replaces only the
current document fact while preserving the same-epoch mutation proof and live
command-guard lease. The sync controller must attest that each stamp equals
its current canonical state, revision is strictly newer than the stored
revision, and edit sequence is monotonic before the reducer sees it; a
same-epoch forged, regressing, or skipped canonical stamp is rejected without
replacing readiness. An advancement with `recoveryEligible=false` freezes and
fails closed. `RecoveryHeadroomLost` affects the session only for the exact
stored current stamp. `CommandChannelLost` affects it only for the exact
current epoch and guard lease UUID, but an exact match is critical in
`SYNCING` as well as `READY`/`DEGRADED`; prove a ready-then-lost guard cannot
later combine with delayed document/mutation facts to enable editing. A
delayed pre-resync `SnapshotAcknowledged`,
`RecoveryCheckpointReady`, `DocumentReadinessAdvanced`,
`RecoveryHeadroomLost`, `MutationChannelReady`, or `CommandChannelLost` is a
typed stale-epoch no-op even when its revision/stamp or lease ID happens to
match the new generation.

A first correlated `RevisionMismatch` in `SYNCING`, `READY`, or `DEGRADED`
consumes the only automatic resync, enters `RESYNCING`, stores
`ResyncTransaction.CapturingRecovery` with its resync ID, exact source stamp,
recovery sequence, and request ID, freezes the old-epoch web model, blocks the
single live command guard, and requests a bounded drain plus
`recovery.export` before any overwrite. It also revokes the logical command
lease immediately. While in `RESYNCING`, every
readiness/headroom/guard event is a no-op even if it carries the still-current
source epoch.

`ProjectionRecoveryCapture` must first validate and durably place the
live-Browser candidate in the SQL-editor-lifetime-owned bounded
`RecoveryCandidateStore`. Only after `store(...)` returns an opaque
`RecoveryCandidateHandle` may it emit
`ResyncRecoveryStored` with the complete matching capture tuple plus a fresh
snapshot-capture ID. The reducer accepts it only against the exact
`CapturingRecovery` transaction and a parent-store entry whose handle is bound
to this activation, resync ID, source stamp, recovery sequence, and request ID.
In one state commit it increments `readinessEpoch` with
overflow checking, clears all readiness and replay state, resets
edit/selection sequences, replaces the transaction with
`PreparingSnapshot(source, targetEpoch, handle, snapshotCaptureId)`, and emits
exactly one correlated canonical snapshot-capture effect. A missing, invalid,
over-limit, allocation-failed, or disposed store enters explicit read-only
recovery/Native fallback; it must not emit the stored event or overwrite the
web model. Epoch exhaustion is
`READINESS_EPOCH_EXHAUSTED`, never wraparound.

`ResyncSnapshotPrepared` must match the current `PreparingSnapshot` resync ID,
target epoch, committed handle, and snapshot-capture ID as well as the
snapshot's target epoch. Only then does it clear the transaction, commit
`RESYNCING -> SYNCING`, and emit `SendSnapshot(snapshot)`.
State is committed before effects execute, so even a re-entrant immediate
Browser acknowledgement is handled in `SYNCING`. Duplicate or stale prepared
events cannot send a second snapshot. A matching
`ResyncSnapshotPreparationFailed` fails closed and offers the already stored
candidate. Prepared-before-store, wrong handle/capture ID, late
recovery-capture failure after the transaction advanced, duplicate prepared,
and every stale correlation are typed no-ops/diagnostics; none transitions or
authorizes overwrite.

Every later mismatch disables Monaco after the allowance was consumed. Run
this matrix from all three permitted source states, including a mismatch after
snapshot acknowledgement but before initial command readiness in `SYNCING`.
Also resync after `N` acknowledged edits plus one rejected batch; prove the
new snapshot/ack reset edit and selection sequences to zero, first new
messages use one, and neither the rejected nor old-epoch sequence becomes
current. No old command proof survives. An optional capability failure records
a disabled capability and diagnostic without failing the session. A critical
failure emits `DisableMonaco` and enters `FAILED`.

Test `CommandReplayLedger` with exact retry, same sequence/different payload,
same message ID/different sequence, concurrent in-flight request, invalid
completion permit, bounded completed-entry eviction, epoch change, and
disposal. Only the `Start` owner may complete an entry. Completion caches the
full immutable `EditorCommandResponse`, including its applied barrier and
rejection, and an exact retry returns the byte-equivalent deterministically
serialized response payload while the fake native handler count remains one.

After disposal, deliver every asynchronous event family—page/handshake,
snapshot/patch/edit/selection acknowledgement, flush/recovery response, probe
completion, command completion, prepared snapshot, Browser failure, timeout,
and duplicate dispose—and prove state remains `DISPOSED` with zero effects and
zero collaborator calls. Repeat representative late events in `FAILED` and
prove `DisableMonaco`/`OfferRecovery` are not emitted twice; only one final
dispose is allowed.

`ArchitectureBoundaryTest` scans production source, compiled class constant
pools, OSGi manifests, and Maven dependency graphs. It rejects prohibited core
dependencies and enforces `ui -> bridge -> core`, with no inverse edge.

- [ ] **Step 2: Run the focused tests and observe failure**

```bash
./mvnw -B -pl tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests,\
tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests -am verify
npm --prefix web test
```

Expected: Java compilation and TypeScript fixture tests fail because the
session and wire types do not exist.

- [ ] **Step 3: Define the JSON Schema source and fixtures**

Use JSON Schema 2020-12. Define a closed `kind` union for:

```text
handshake.request
handshake.response
session.mode
document.snapshot
document.snapshotAck
document.editBatch
document.patch
document.patchAck
document.ack
selection.update
selection.ack
barrier.flush.request
barrier.flush.response
command.request
command.response
recovery.export.request
recovery.export.response
failure
```

Define the common scalar constraints once under `$defs`: protocol versions,
session/message IDs, safe counters, int32 text offsets, and bounded strings.
Each root `oneOf` branch is nevertheless a complete closed object with
`type: object`, `additionalProperties: false`, the same exact six required
property names, references to the four common scalar definitions, one literal
`kind`, and one typed payload reference. Set `additionalProperties: false` on
every payload and nested closed object as well.

Do not compose envelope variants with `allOf` or rely on
`unevaluatedProperties`: `json-schema-to-typescript@15.0.4` weakens that shape
to optional discriminants and an open index signature. The small duplication
of six envelope property names is deliberate. A contract test proves that
every branch has the identical common references and required-field set, so
constraints still have a single source.

Every envelope requires `protocolMajor`, `protocolMinor`, `sessionId`,
`messageId`, `kind`, and `payload`. In protocol 1.0,
`protocolMajor` is integer constant `1` and `protocolMinor` is integer constant
`0`; both wrong-version fixtures are rejected before `WireEnvelope`
construction. A future compatible minor is a reviewed schema/protocol release
that changes the constant and compatibility tests rather than silently
widening the current parser.

Every JSON integer that reaches TypeScript has a schema range that preserves
identity as a JavaScript `number`. Epochs, revisions, document stamps, and
sequence values use shared integer definitions bounded by
`Number.MAX_SAFE_INTEGER` (`9_007_199_254_740_991`), with zero or one as the
semantic minimum. Text offsets and lengths additionally stop at
`Integer.MAX_VALUE` because Eclipse document APIs use int offsets. Never
accept a Java `long` value that TypeScript would round, and never treat the
Jackson number-length limit as a precision guarantee. The shared max-safe
fixture is accepted and the max-safe-plus-one fixture is rejected by both
validators and by the Java decoder/mapper contract.

Bound every identifier and string-valued metadata field so the 64 KiB
journal-entry metadata constant is mechanically provable. Every
document-, selection-, command-, session-mode-, and flush-bearing payload
requires an integer `readinessEpoch >= 1`. Every document-bearing message also
requires the applicable `revision` and `documentStamp`; every host-to-web
`document.ack` also requires typed `recoveryEligible`. Edit payloads require
`baseRevision`, `baseDocumentStamp`, `clientSequence`, and an array of
`{offset,length,text}` with non-negative integer offsets/lengths. Its schema
`maxItems` and both semantic validators equal
`ProtocolLimits.MAX_EDITS_PER_BATCH == 1_024`; the 8 MiB byte limit alone does
not bound sort/validation work. Reject the count before allocating or sorting
the full batch, and complete schema/size/count validation before scheduling
canonical mutation on the SWT thread. Selection updates and acknowledgements
require revision, stamp, and a monotonic
`selectionSequence`. Command requests are typed intents: they require the
epoch, a positive monotonic `commandSequence`, and request `messageId`; an
execute intent also names the latest locally dispatched selection sequence.
They may not supply an allegedly authoritative revision barrier. The only
trusted barrier is produced by the correlated drain, and command responses
echo the sequence/request ID plus the exact applied barrier when a native
handler ran. The wire schema has no client-settable `origin` property
(`additionalProperties: false`); the bridge mapper assigns `WEB`, while only
the host guard can construct `NATIVE`. Flush request/response payloads
likewise carry a monotonic `flushSequence` plus their UUID correlation.

Directions are part of the contract: `document.snapshotAck` is the web-to-host
acknowledgement that the initial or resync snapshot was applied;
`document.patchAck` is the web-to-host acknowledgement of a canonical patch;
and `document.ack` is only the host-to-web acknowledgement of a Monaco edit.
No mapper may substitute one for another.

Edit, selection, flush, recovery-export, and both command-origin sequence
namespaces are scoped to one readiness epoch. Every initial/resync
`DocumentSnapshot` and matching
`SnapshotAck` explicitly carry `resetEditSequence=0` and
`resetSelectionSequence=0`; the web clears only its drained old-epoch queues
after applying that snapshot, and the first new sequence is `1`.
`SnapshotAcknowledged` therefore constructs initial `DocumentReadiness` with
the acknowledged reset edit sequence instead of guessing a high-water mark.
An epoch change clears replay ledgers. Rejected old-epoch batches never advance
the new high-water marks.

`session.mode` is host-to-web and carries `READ_ONLY`, `EDITABLE`, or `FAILED`
plus a stable optional reason. Integrated production boot is fail-closed
`READ_ONLY`; only a current-epoch `EDITABLE` message may unlock Monaco.
`barrier.flush.request` is host-to-web and atomically freezes input.
The web client drains all already-dispatched document and selection messages,
waits for their typed acknowledgements, then returns
`barrier.flush.response` with the correlated UUID, acknowledged
`RevisionBarrier`, and latest dispatched edit/selection sequences. The host
accepts the barrier only when the response epoch and correlation match, both
dispatched sequences equal their acknowledged sequences, and the entire
barrier equals current canonical controller state. Timeout, local events
after freeze, or mismatch is `FLUSH_BARRIER_FAILED`; native code is not
invoked.

Command execution is at-most-once per Monaco activation, epoch, and origin.
`CommandReplayLedger` has independent `WEB` and `NATIVE` sequence namespaces,
serializes the shared native transaction, and retains the 256 most recent
completed `(origin, epoch, commandSequence, messageId,
canonical-payload-hash, response)` entries. The bridge mapper always assigns
`WEB`; origin is not a client-controlled wire field. Native toolbar/menu
invocations receive a host-allocated sequence from the separate `NATIVE`
high-water mark, so they cannot consume or collide with a web sequence.

The ledger is cleared on epoch change/activation disposal. An exact retry
returns the cached full `EditorCommandResponse` through its completion permit
without re-entering the flush or native handler. Within one
origin, reusing a sequence or message ID with different content, regressing a
sequence, or issuing a second in-flight command is rejected with
`NON_MONOTONIC_SEQUENCE`. Eviction never affects an in-flight entry. The
reentrancy guard is not the replay mechanism.

Define the complete recovery request/response payload and every stable failure
code exactly as enumerated in the Task 2 interface block; later tasks must not
add an inferred code or change the wire union. Task 9 implements the UI
without changing the schema. Enforce `ProtocolLimits` in both Java
and TypeScript semantic validation. JSON Schema `maxLength` is not trusted as
a UTF-16 measurement by itself. A 10 MiB ASCII SQL recovery response must fit,
while an over-limit response is rejected rather than truncated.
The recovery response carries the source epoch/revision/stamp, exact
dispatched and acknowledged edit/selection high-water marks, and full bounded
projection text; it is sufficient to construct `RecoveryCandidate` before a
resync overwrite. It never claims that a Browser event absent from that
export was captured. Recovery requests carry a monotonic `recoverySequence`
and UUID `requestId`; responses echo both. The host accepts exactly one
response only while that tuple is the current pending request. Delayed,
duplicate, wrong-epoch, or wrong-correlation responses are typed no-ops and
can never authorize `ResyncRecoveryStored`.

- [ ] **Step 4: Configure deterministic wire contracts**

Keep `protocol/schema/editor-bridge.schema.json` as the only validation
contract. Its root remains the closed `oneOf` message union from Step 3.
Generate the TypeScript discriminated union, but do not add a Java
schema-to-record processor: the available generator does not model this union,
and deriving a second weakened schema merely to generate six envelope fields
adds build and supply-chain complexity without type safety.

Create this small handwritten bridge-private boundary type:

```java
public record WireEnvelope(
    int protocolMajor,
    int protocolMinor,
    String sessionId,
    String messageId,
    String kind,
    JsonNode payload) {}
```

It is not a domain message and never crosses into core. Raw JSON is parsed to
a bounded tree, validated against the original closed schema, and only then
converted to `WireEnvelope`. Before tree construction, reject an over-limit
UTF-16 length and then count UTF-8 bytes without allocating another full byte
array. Configure the private Jackson factory with a maximum nesting depth of
32, maximum decoded string length of
`ProtocolLimits.MAX_TEXT_UTF16_CODE_UNITS`, and maximum number length of 20.
These parser limits are fixed code constants, not caller options.

`BridgeSchemaContractTest` reflects the record components and proves their
names and primitive/object shapes match the six properties present in every
root branch. It also proves that every branch is closed, requires exactly those
six properties, references the same four common scalar definitions, has one
unique `kind` const and one payload reference, and uses protocol constants
1.0.

`BridgeMessageMapperTest` reads that complete branch kind set and proves it
equals `BridgeMessageMapper.supportedKinds()` exactly. More importantly, there
is one canonical valid fixture for every one of the 18 union branches. The
same fixture is accepted by Ajv and NetworkNT, then passed through
`BridgeMessageDecoder` and `BridgeMessageMapper`; the Java test asserts the
exact immutable core variant and every mapped payload field. Kind-set parity
alone is not accepted as mapper coverage. Schema fields, variants, or payload
extraction cannot change without an explicit mapping/test change, while there
is no second Java schema or annotation-processor dependency to drift.

Install exact `json-schema-to-typescript@15.0.4` and make
`web/scripts/generate-protocol.mjs` compile the same schema to
`web/src/generated/editor-bridge.d.ts`. The complete closed branch layout is
mandatory because it produces a real discriminated union rather than the
generator's weakened `allOf` output.

Install exact `ajv@8.20.0` under `dependencies`, not `devDependencies`,
because selected Ajv runtime-helper code is embedded in the released browser
validator and must appear in production audit, SBOM, and license inventory.
The schema compiler itself remains build-time-only and is tree-excluded from
the browser artifact. Instantiate `Ajv2020` from `ajv/dist/2020.js` with
`code: { source: true }` and compile the authoritative schema at build time.
Ajv standalone output is an intermediate, not a browser artifact: even its ESM
mode can emit CommonJS `require(...)` calls for `ajv/dist/runtime/*` helpers
such as Unicode length.

Install exact build-time-only `esbuild@0.28.1`, `acorn@8.18.0`, and
`eslint-scope@9.1.2` under `devDependencies`; keep
`json-schema-to-typescript@15.0.4` there as well. Have
`generate-protocol.mjs` emit temporary standalone CommonJS through
`ajv/dist/standalone`, then invoke esbuild's JavaScript API with
`bundle: true`, `platform: "browser"`, `format: "esm"`, a fixed `es2022`
target, no source map, and retained legal comments. Bundle every pinned Ajv
runtime helper into the deterministic committed
`web/src/generated/validate-editor-bridge.mjs`, generate its declaration file,
and delete the temporary intermediate. No Ajv helper is externalized.
`validateEnvelope.ts` imports only that final self-contained module.
Preserve Ajv's MIT notice in the web bundle and record the exact bundled
helper inputs from the esbuild metafile for the release inventory.

Production code must not compile a schema or invoke dynamic `Function`; the
strict CSP must not add `unsafe-eval`. Raw substring scanning is forbidden:
valid esbuild output can contain a bound `__require` helper and harmless Ajv
metadata strings containing the word `require`.

Instead, the semantic verifier parses the final generated module as ESM with
the pinned Acorn, resolves lexical bindings with the pinned `eslint-scope`,
and rejects unresolved/global direct `require` and `eval` `CallExpression`
nodes plus both `CallExpression` and `NewExpression` uses of the unresolved
global `Function` identifier. It also requires the esbuild
metafile's final output to have zero external imports and its input graph to
contain no Ajv compiler module; only the temporary compiled schema and pinned
`ajv/dist/runtime/*` helpers may contribute. Bound esbuild helpers and string
literals are not findings. Then it imports the module and validates all
fixtures under Node's
`--disallow-code-generation-from-strings`. Task 3 additionally runs the same
validator in the real Browser page under the exact production CSP and fails
on every CSP console violation.

`verify-generated-protocol.mjs` and
`tests/protocolTypes.contract.ts` are semantic gates, not snapshot-only checks.
They require all six envelope fields and all 18 exact kind/payload pairings,
accept one complete object per variant, and use `@ts-expect-error` cases to
reject an unknown envelope field and a wrong kind/payload pair. They also fail
if the exported wire union contains `any`, `unknown`, or a string/number index
signature. Configure `tsconfig.protocol-contract.json` to compile this file
strictly against the generated declaration.

Add `protocol:generate`, `protocol:types`, and `protocol:check` scripts.
`protocol:check` regenerates every generated type/validator artifact into a
temporary path, fails on any diff, runs the semantic verifier, and runs the
strict compile-only contract. Until Task 3 installs Vitest, set the Task 2
test script to
`node --disallow-code-generation-from-strings --test tests/protocolFixtures.test.ts`
and keep protocol tests within Node 24.18.1's erasable TypeScript syntax.
Task 3 deliberately replaces this runner after installing its pinned
test toolchain.

Update `ci.yml` in this task to run
`npm --prefix web run protocol:check` after `npm ci` on every pull request.
Task 2 does not rely on Task 3's future Maven-owned web lifecycle; stale
generated TypeScript must already fail the protected branch check.

Create a normal Maven `jar` module for the private JSON runtime. Shade
`com.networknt:json-schema-validator:2.0.4` and its exact Jackson 2 dependency
closure into one jar with `maven-shade-plugin:3.6.2`; keep the original package
names because the decoder and `WireEnvelope` use Jackson types, merge service
descriptors, exclude optional YAML/ITU format modules that the schema does not
use, and preserve all notices and licenses. Isolation comes from the bridge
bundle's private class path, not bytecode relocation. Use
`maven-dependency-plugin:3.11.0` to copy the single deterministic artifact to
`bridge/lib/bridge-json-runtime.jar`. The bridge manifest must declare
`Bundle-ClassPath: .,lib/bridge-json-runtime.jar`; `build.properties` must
include that jar, and no shaded package may be exported. Add the third-party
module before the bridge module in the root reactor.

Node generation and contract tests instantiate `Ajv2020` from
`ajv/dist/2020.js`; the default Ajv export is draft-07 and is forbidden.
Browser runtime validation uses only the generated standalone module described
above. Construct NetworkNT with
`SchemaRegistry.withDefaultDialect(SpecificationVersion.DRAFT_2020_12)`.
`BridgeMessageDecoder` validates the original closed JSON Schema 2020-12 union
before constructing the explicit `WireEnvelope` and enforces the message-size
bound supplied by its constructor. `BridgeMessageMapper` uses an explicit
manual switch over the validated string `kind`, reads bounded fields from the
opaque payload, and maps each variant into immutable core value types. Its
default branch fails closed, while the source-schema parity test makes that
branch unreachable for every accepted schema variant. The wire envelope never
crosses the bridge boundary. `validateEnvelope.ts` validates the same fixtures.
Both validators must reject `unknown-envelope-property.json`; that fixture
proves every complete branch is closed by `additionalProperties: false`. The
schema `$schema` URI, explicit Ajv2020 constructor, and explicit NetworkNT
dialect are asserted independently. Both validators also reject unknown
commands, wrong protocol versions, and unsafe integers at the schema/decoder
boundary.

`scripts/verify-bridge-closure.sh` must compare the resolved dependency tree
with an allowlist, inspect the installed OSGi bundle for the embedded runtime,
reject any export/import of the embedded JSON packages, and verify retained
license files.

- [ ] **Step 5: Implement the deterministic core state machine**

Use exhaustive switch expressions. Invalid state/event pairs produce a typed
`FailureEffect(INVALID_TRANSITION)` and `FAILED`, with two terminal rules:
`DISPOSED` absorbs every later event as `NoEffect`, and `FAILED` absorbs every
event except `DisposeRequested`. `DisposeRequested` transitions any
non-disposed state to `DISPOSED`, releases resources exactly once, and is
idempotent thereafter. Late callbacks can never resurrect state or repeat
destructive effects against disposed resources.

Implement and test this lifecycle:

| Current state | Event | Next state | Required effect |
|---|---|---|---|
| `NEW` | `ProbeStarted` | `PROBING` | `RunCapabilityProbes` |
| `PROBING` | `ProbePassed` | `PROBING` | `RecordCapabilityPass` |
| `PROBING` | optional `ProbeFailed` | `PROBING` | `RecordDiagnostic` |
| active | critical `ProbeFailed` | `FAILED` | `DisableMonaco` |
| `PROBING` | `ProbeCompleted` | `LOADING` | `LoadPage` |
| `LOADING` | `PageLoaded` | `HANDSHAKING` | `SendHandshake` |
| `HANDSHAKING` | `HandshakeAccepted` | `SYNCING` | `SendSnapshot`, `KeepReadOnly` |
| `SYNCING` | any readiness event with a fact still missing | `SYNCING` | `RecordCapabilityPass`, `KeepReadOnly` |
| `SYNCING` | any readiness event completing all three facts | `READY` or `DEGRADED` | `EnableEditing` exactly once |
| `READY` or `DEGRADED` | duplicate readiness event | unchanged | `NoEffect` |
| `READY` or `DEGRADED` | current-epoch `DocumentReadinessAdvanced(..., true)` | unchanged | atomically replace current document readiness |
| active | stale-epoch readiness/headroom/lease event | unchanged | typed diagnostic, `NoEffect` |
| `READY` | `OptionalCapabilityLost` | `DEGRADED` | `DisableOptionalFeature` |
| `DEGRADED` | another `OptionalCapabilityLost` | `DEGRADED` | `DisableOptionalFeature` |
| `DEGRADED` | `OptionalCapabilityRecovered` while another remains disabled | `DEGRADED` | `EnableOptionalFeature` |
| `DEGRADED` | last `OptionalCapabilityRecovered` | `READY` | `EnableOptionalFeature` |
| `SYNCING`, `READY`, or `DEGRADED` | first correlated `RevisionMismatch` | `RESYNCING` | consume allowance, store `CapturingRecovery`, revoke logical command lease, block physical guard, `KeepReadOnly`, `DrainAndCaptureRecovery` |
| `RESYNCING` | readiness/headroom/guard event | `RESYNCING` | `NoEffect` |
| `RESYNCING` in `CapturingRecovery` | exact matching `ResyncRecoveryStored` with committed handle | `RESYNCING` in `PreparingSnapshot` | atomically increment epoch/reset facts and sequences, store authorization, `CaptureSnapshot` once |
| `RESYNCING` in `CapturingRecovery` | exact matching `ResyncRecoveryCaptureFailed` | `FAILED` | `KeepReadOnly`, `OfferRecovery`, never overwrite projection |
| `RESYNCING` in `PreparingSnapshot` | exact matching `ResyncSnapshotPrepared` | `SYNCING` | clear transaction; after state commit, `SendSnapshot` exactly once |
| `RESYNCING` in `PreparingSnapshot` | exact matching `ResyncSnapshotPreparationFailed` | `FAILED` | `KeepReadOnly`, `OfferRecovery` using committed handle |
| `RESYNCING` or `SYNCING` | out-of-phase, wrong-correlation, late, or duplicate resync callback | unchanged | typed diagnostic, `NoEffect` |
| active | current-stamp `RecoveryHeadroomLost` | `FAILED` | `DisableMonaco`, `OfferRecovery` |
| `SYNCING`, `READY`, or `DEGRADED` | exact stored-lease `CommandChannelLost` | `FAILED` | `DisableMonaco`; stale or wrong lease remains `NoEffect` |
| active | later `RevisionMismatch` | `FAILED` | `DisableMonaco` |
| active | `BridgeFailed` | `FAILED` | `DisableMonaco` |
| any | `DisposeRequested` | `DISPOSED` | `DisposeResources` once |
| `FAILED` | event other than `DisposeRequested` | `FAILED` | `NoEffect` |
| `DISPOSED` | any event | `DISPOSED` | `NoEffect` |

`CircuitBreaker` is an immutable value with only
`AVAILABLE -> CONSUMED -> TRIPPED` transitions; it exposes no reset method.
It is carried in `SessionContext`, so a successful resync cannot replenish the
allowance; Task 8 persists the latest value in the longer SQL-editor lifetime
across Monaco activations. The initial activation epoch is `1`. The first
mismatch freezes/captures under the source epoch and installs a
`CapturingRecovery` transaction. Only an exact stored bounded projection
candidate replaces it with `PreparingSnapshot`, authorizes the checked epoch
increment, and clears pending startup stamps, current document readiness,
mutation proof, logical command lease, and per-epoch sequence/replay state.
Capture failure never sends a canonical overwrite. Arithmetic fails closed at
`Long.MAX_VALUE`.

Readiness events are no-ops throughout `RESYNCING`, then old-epoch events
remain typed no-ops in `SYNCING`. A prepared event is accepted only through
the matching post-store authorization; matching failure, duplicate, and late
events follow the explicit rows above rather than the general invalid-pair
rule. The reducer commits `SYNCING` before executing the prepared snapshot's
send effect; tests use a re-entrant Browser callback that acknowledges during
`SendSnapshot` and prove it is accepted, while duplicate prepared events never
resend.

During `SYNCING`, matching current-epoch `SnapshotAcknowledged` and
`RecoveryCheckpointReady` are combined into `currentDocument`; neither fact
alone is qualified. `pendingSnapshotAcknowledgement` stores the full
`SnapshotAck`, including reset edit/selection sequences, until the checkpoint
arrives; it is not reduced to a stamp. Mismatched evidence never combines. Task 6 produces the
checkpoint event only for initial/resync qualification, and produces
`MutationChannelReady(epoch)` only after a real mutation-channel and compound
undo probe. Task 7 produces `CommandChannelReady(epoch, guardLeaseId)` only
after native command routing and that exact live guard are proven. Loss of the
exact stored lease is critical even while other `SYNCING` facts are still
missing; it can never leave a stale fact that later unlocks editing.

After editing starts, Task 6 uses `DocumentReadinessAdvanced` for each
successfully acknowledged Monaco edit and acknowledged canonical patch. That
event is valid in `READY` and `DEGRADED`, atomically replaces
`currentDocument`, and preserves same-epoch mutation and command facts. It
never reuses `RecoveryCheckpointReady` as a post-ready transition. All
readiness events validate the epoch before state/event dispatch. The sync
controller also validates an advancement against its exact current canonical
stamp and strictly increasing revision; headroom loss must match the stored
stamp, and guard loss must match the stored lease UUID. A delayed or
same-epoch-mismatched event is a typed no-op/rejection rather than
`INVALID_TRANSITION`.

- [ ] **Step 6: Run protocol and core verification**

```bash
npm --prefix web run protocol:generate
npm --prefix web run protocol:check
npm --prefix web test
./mvnw -B -pl repository -am verify
bash scripts/verify-bridge-closure.sh repository/target/repository
./mvnw -B -pl tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests,\
tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests -am verify
./mvnw -B verify
```

Expected: generated files are stable, all valid fixtures deserialize/validate,
invalid fixtures are rejected with stable reason codes, DTO-to-core mappings
round-trip with one exact mapping assertion per union branch, the generated
TypeScript union is closed and discriminated, the standalone browser validator
requires no dynamic code generation, the Java validator loads from the
installed OSGi bundle, the runtime dependency closure is complete, and
boundary tests pass.

- [ ] **Step 7: Commit protocol and core lifecycle**

```bash
git add protocol bundles third-party scripts web tests pom.xml \
  .github/workflows/ci.yml
git commit -m "feat: add typed bridge protocol and session lifecycle"
```

Stop and open the Task 2 draft PR.

### Task 3: Standalone Monaco web application

**Files:**

- Create: `web/index.html`
- Create: `web/vite.config.ts`
- Create: `web/vitest.config.ts`
- Create: `web/playwright.config.ts`
- Create: `web/eslint.config.mjs`
- Create: `web/security/content-security-policy.txt`
- Create: `web/src/editor/editorOptions.ts`
- Create: `web/src/editor/createSqlEditor.ts`
- Create: `web/src/bridge/BridgeClient.ts`
- Create: `web/src/bridge/HostCommand.ts`
- Create: `web/src/bridge/MockBridgeClient.ts`
- Modify: `web/src/main.ts`
- Create: `web/tests/editorOptions.test.ts`
- Create: `web/tests/editor.spec.ts`
- Create: `web/tests/bridgeClient.test.ts`
- Create: `web/scripts/verify-dist.mjs`
- Modify: `web/pom.xml`
- Modify: `web/META-INF/MANIFEST.MF`
- Modify: `web/build.properties`
- Modify: `web/package.json`
- Modify: `web/package-lock.json`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**

- Consumes: generated protocol types and protocol-major value from Task 2.
- Produces:

```ts
export interface BridgeClient {
  handshake(): Promise<HandshakeResponse>;
  acknowledgeSnapshot(acknowledgement: SnapshotAck): Promise<void>;
  acknowledgePatch(acknowledgement: CanonicalPatchAck): Promise<void>;
  sendEdit(batch: EditBatch): Promise<DocumentAck>;
  updateSelection(selection: PrimarySelection): Promise<SelectionAck>;
  requestCommand(command: HostCommand): Promise<CommandResult>;
  respondToFlush(response: FlushBarrierResponse): Promise<void>;
  respondToRecoveryExport(response: RecoveryExportResponse): Promise<void>;
  onSessionMode(listener: (mode: SessionMode) => void): Disposable;
  onSnapshot(listener: (snapshot: DocumentSnapshot) => void): Disposable;
  onCanonicalPatch(listener: (patch: CanonicalPatch) => void): Disposable;
  onFlushRequest(
    listener: (request: FlushBarrierRequest) => void
  ): Disposable;
  onRecoveryExportRequest(
    listener: (request: RecoveryExportRequest) => void
  ): Disposable;
  dispose(): void;
}

export type HostCommand =
  | { kind: "save" }
  | { kind: "undo" }
  | { kind: "redo" }
  | { kind: "format" }
  | { kind: "execute"; mode: "statement" | "script" };
```

- [ ] **Step 1: Pin tooling and define executable npm scripts**

Install exact `monaco-editor@0.56.0`. Add npm override
`dompurify: 3.4.12`. Keep Task 1's exact `typescript@6.0.3`; install exact
`vite@8.2.0`, `vitest@4.1.10`, `eslint@10.8.0`, `@eslint/js@10.0.1`,
`typescript-eslint@8.65.0`, and `@playwright/test@1.62.1` as development
dependencies. Use `--save-exact`; npm ranges are forbidden. Commit the
lockfile. Preserve Task 2's exact production Ajv entry and its exact
development-only schema generator, direct esbuild, Acorn, and scope-analysis
tooling; direct esbuild remains build-time-only even if Vite also has a
transitive copy.

Create strict flat ESLint, Vitest, Vite, and Playwright configs, but no editor
implementation. Replace Task 1's placeholder scripts with:

```json
{
  "scripts": {
    "lint": "eslint . --max-warnings=0 && tsc --noEmit",
    "test": "vitest run",
    "test:browser": "playwright test",
    "build": "vite build",
    "verify:dist": "node scripts/verify-dist.mjs"
  }
}
```

Preserve Task 2's `protocol:generate` and `protocol:check` scripts. Configure
Vitest to exclude Playwright `*.spec.ts` files and Playwright to use only its
browser tests.

- [ ] **Step 2: Write failing editor-option and browser tests**

Assert that `createEditorOptions()` enables automatic layout, minimap, smooth
scrolling, multiple cursors, and SQL language while leaving Monaco's standard
add-next-occurrence keybinding active. Its production/default mode must set
`readOnly: true`; there is no writable interval during integrated boot.
Browser tests must verify
`Ctrl+D`/`Meta+D`, two-cursor typing and paste, vertical and horizontal wheel
scrolling without outer-page scroll, find/open/next/close, keyboard navigation,
typed host-command emission, and disposal of the model, subscriptions, and
worker resources. Tests that type use an explicit standalone
`MockHarness(initialMode: EDITABLE)`; no production code infers editability
from a missing bridge or a successful handshake.

Make `web/security/content-security-policy.txt` the single shared policy
source consumed by Playwright now and by the Task 4 asset server later. Its
exact value is:

```text
default-src 'none'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; worker-src 'self' blob:
```

There is deliberately no `unsafe-eval`. Configure the Playwright web server to
return this exact response header. A browser test imports the final generated
validator through the application, accepts a canonical valid fixture, rejects
an invalid fixture, and fails on every `securitypolicyviolation` event or CSP
console error. This is the exact-CSP half of Task 2's earlier no-code-generation
gate.

- [ ] **Step 3: Run web tests and observe a behavioral red phase**

```bash
npm --prefix web test
npm --prefix web exec -- playwright install chromium
npm --prefix web run test:browser
```

Expected: genuine test/compile failure because editor modules do not exist;
the test runners and browsers must already be installed. Do not satisfy the
red phase with skipped tests or an expected missing-runner process error.

```bash
npm --prefix web audit --omit=dev
```

Expected: no unresolved high or critical production vulnerability. Stop if the
override breaks Monaco tests or audit remains unsafe.

- [ ] **Step 4: Implement the strict TypeScript editor shell**

Use `strict: true` and no `any`. Configure:

```ts
{
  language: "sql",
  automaticLayout: true,
  minimap: { enabled: true },
  smoothScrolling: true,
  scrollBeyondLastLine: false,
  multiCursorModifier: "alt",
  mouseWheelZoom: false
}
```

Keep Monaco-local commands local. Intercept only typed host commands. Use a
mock bridge in standalone tests. The integrated editor starts read-only,
ignores stale-epoch `session.mode`, and becomes writable only after an
explicit current-epoch `EDITABLE` message. `READ_ONLY`, `FAILED`, disposal,
and every flush request synchronously revoke input before any promise is
awaited. Task 3 implements the typed listeners and a deterministic flush
queue shell, but no production path sends `EDITABLE`; Task 7 owns that signal.
Bundle ESM workers through Vite and prohibit external asset URLs.

- [ ] **Step 5: Make Maven own the reproducible web build**

Bind `com.github.eirslett:frontend-maven-plugin:2.0.2` in `web/pom.xml` to
install Node 24.18.1/npm 11.16.0 into Maven's build directory and execute, in
order, `npm ci`, `npm run protocol:check`, `npm run lint`, `npm test`, and
`npm run build`, followed by `npm run verify:dist`. Runtime bundles must not
contain Node or npm.

Make `web` an `eclipse-plugin` bundle containing `dist/`, protocol metadata,
the shared CSP file, and required notices, including Ajv's MIT notice. Add
`dist/` and
`security/content-security-policy.txt` to `bin.includes`; no UI bundle may
duplicate the assets. `scripts/verify-dist.mjs` rejects source maps containing
absolute paths, remote URLs, unlisted workers, files not reachable from
`index.html`, unresolved external imports, or unbound direct
`require`/`eval` calls and unbound global `Function` calls/constructors. It
uses the same exact AST node and lexical-binding rules as Task 2 instead of raw
substring matching, so bound esbuild helpers and Ajv metadata strings are not
false positives. A clean `./mvnw verify` must create the packaged asset bundle
without a prior manual npm command.

Update `.github/workflows/ci.yml` to install the Playwright 1.62.1-pinned
Chromium after `npm ci` and run `npm run test:browser` in addition to the
Maven-owned unit/build/dist gates. Browser install or tests may not be skipped
on pull requests.

- [ ] **Step 6: Run web verification**

```bash
npm --prefix web run lint
npm --prefix web test
npm --prefix web run build
npm --prefix web run verify:dist
npm --prefix web exec -- playwright install --with-deps chromium
npm --prefix web run test:browser
./mvnw -B clean verify
```

Expected: all checks pass and `web/dist` contains only local application,
Monaco, and worker assets; the built p2 repository contains that exact web
bundle and no Node runtime.

- [ ] **Step 7: Commit the standalone editor**

```bash
git add web .github/workflows/ci.yml
git commit -m "feat: add standalone Monaco SQL editor"
```

Stop and open the Task 3 draft PR.

### Task 4: SWT Browser and loopback-host feasibility checkpoint

**Files:**

- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/browser/LoopbackAssetServer.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/browser/AssetServerLease.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/browser/BrowserHost.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/browser/SwtBrowserHost.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/browser/BridgeFunction.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/browser/WebBundleAssets.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/BrowserCapabilityProbe.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/lifecycle/DisposableScope.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/LoopbackAssetServerTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/DisposableScopeTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.native.ui.tests/pom.xml`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.native.ui.tests/META-INF/MANIFEST.MF`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.native.ui.tests/build.properties`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.native.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/nativeui/SwtBrowserHostTest.java`
- Create: `releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.native.test.target/pom.xml`
- Create: `releng/io.github.bakhtiiartashbolotov.dbeaver.monaco.native.test.target/io.github.bakhtiiartashbolotov.dbeaver.monaco.native.test.target.target`
- Create: `scripts/run-native-browser-smoke.sh`
- Create: `scripts/run-native-browser-smoke.ps1`
- Create: `scripts/prepare-dbeaver-product.sh`
- Create: `scripts/prepare-dbeaver-product.ps1`
- Create: `releng/baseline/dbeaver-ce-26.1.0-macos-x86_64.dmg.sha256`
- Create: `releng/baseline/dbeaver-ce-26.1.0-macos-aarch64.dmg.sha256`
- Create: `releng/baseline/dbeaver-ce-26.1.0-windows-x86_64.zip.sha256`
- Create: `.github/workflows/browser-matrix.yml`
- Create: `docs/evidence/task-4-browser-spike.md`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/pom.xml`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/META-INF/MANIFEST.MF`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/build.properties`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/pom.xml`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/META-INF/MANIFEST.MF`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/build.properties`
- Modify: `pom.xml`

**Interfaces:**

- Consumes: Task 3 `web/dist` and Task 2 handshake types.
- Produces:

```java
public interface AssetServerLease extends AutoCloseable {
    URI pageUri();
    @Override void close();
}

public interface BrowserHost extends AutoCloseable {
    CapabilityReport probe();
    void load(URI pageUri);
    void send(String validatedJson);
    @Override void close();
}
```

- The lease creates, owns, and destroys its opaque session token. Callers
  cannot choose it or transfer it to another lease. Application code treats
  `pageUri()` as opaque and never parses or logs it; the Browser may reuse the
  URI only within that live lease, and it becomes invalid after `close()`.
- `SwtBrowserHost` is the final SWT implementation behind `BrowserHost`;
  mutable SWT state remains private and ordinary tests receive the interface.

- [ ] **Step 1: Write failing server, lifecycle, and Browser tests**

Test loopback-only binding, random port, token rejection, the exact shared CSP
header, missing asset 404, external navigation cancellation, reverse
idempotent disposal, and handshake round trip. Verify that the caller cannot
construct a page URI from a caller-chosen token and that every served byte and
the policy source come from the installed web OSGi bundle rather than a
development filesystem.

- [ ] **Step 2: Run focused PDE tests and observe failure**

```bash
./mvnw -B -pl tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests \
  -am verify
```

Expected: compilation failure because host types do not exist.

- [ ] **Step 3: Implement the bounded local host**

Use JDK HTTP server APIs and bind exactly to the literal IPv4 address returned
by `InetAddress.getByAddress(new byte[] {127, 0, 0, 1})` and port `0`; do not
use hostname resolution or `getLoopbackAddress()`. Each lease generates and
owns at least 128 bits of token entropy. Allow only hash-manifested paths from
the installed `io.github...monaco.web` bundle. Load
`security/content-security-policy.txt` from that same installed signed bundle
and return it byte-for-byte as the CSP header; it is not a served asset or a
caller option. Refuse to start if the policy is absent, differs from the
Task 3 tested value, or contains `unsafe-eval`.

`DisposableScope.close()` must be idempotent and close registrations in reverse
order. The process server uses reference-counted leases and stores no editor
reference. Requests reject traversal, alternate host headers, methods other
than `GET`/`HEAD`, missing tokens, and tokens from another lease. Never log a
token-bearing URI.

- [ ] **Step 4: Implement Browser capability probes**

Probe page load, JavaScript evaluation, JavaScript→Java `BrowserFunction`,
Java→JavaScript message delivery, worker load, clipboard/key event visibility,
and disposal. Do not make the editor writable in this task.

Add a root `native-ui` Maven profile whose only additional module is
the native test target followed by
`tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.native.ui.tests`.
Default `./mvnw verify` runs server/lifecycle mocks only and discovers no
native test class, so it needs neither skipped tests nor a display. The native
target combines a `Directory` location at
`${system_property:dbeaver.product.path}` with the exact Task 1 JUnit Maven
roots. The native module overrides target selection to that artifact.

Both native profiles are inactive by default. Use
`maven-enforcer-plugin:3.6.3` to reject a missing, relative, or nonexistent
`dbeaver.product.path` before test execution. Configure
`tycho-surefire-plugin:5.0.3` with `providerHint=junit5`,
`failIfNoTests=true`, `useUIHarness=true`, `useUIThread=true`, and the exact
verified DBeaver application/product IDs captured in Task 1. Run every SWT
test under a real display with:

```bash
./mvnw -B -Pnative-ui \
  -Ddbeaver.product.path=/absolute/verified/dbeaver-product verify
```

- [ ] **Step 5: Run the native platform matrix and record evidence**

Create `browser-matrix.yml` with `ubuntu-24.04` x86_64, `windows-2025`
x86_64, `macos-15-intel` x86_64, and `macos-15` Apple Silicon jobs. Pin every
third-party action to a full commit SHA, and fail before download unless the
native architecture query and `runner.arch` match the committed architecture
key.
Each job verifies the committed SHA-256 for the exact official DBeaver 26.1.0
product, clones the verified extracted product into an isolated per-job
temporary installation, installs the just-built feature there without
mutating the baseline, and launches the native SWT/PDE smoke application with
a real display through `-Pnative-ui`. The shell and
PowerShell launchers
must have the same probe contract and return non-zero on a missing result.
The preparation scripts accept only a `(version, os, architecture)` key from a
committed filename/URL/checksum allowlist; they do not accept caller-provided
URLs or digests. They print the absolute verified product path for the workflow
to pass as `-Ddbeaver.product.path`; every job records that path only as a
redacted workspace-relative label.

In `docs/evidence/task-4-browser-spike.md`, record workflow run URL, commit
SHA, OS image, architecture, DBeaver archive SHA-256, SWT Browser
backend/version, and each probe result. Record only a redacted origin template
such as `http://127.0.0.1:<ephemeral>/<redacted>/`; never record the actual
token-bearing check URL. Every critical probe must pass on all four
OS/architecture rows or the task stops for a go/no-go decision.

- [ ] **Step 6: Run full verification and commit**

```bash
./mvnw -B clean verify
```

Expected: the default reactor passes without a display, and the required
`browser-matrix.yml` run passes `-Pnative-ui` on all four native rows.

```bash
git add pom.xml bundles tests scripts releng .github/workflows/browser-matrix.yml \
  docs/evidence
git commit -m "feat: prove secure SWT Browser host"
```

Stop and open the Task 4 draft PR. Do not register the SQL presentation until
the cross-platform checkpoint is accepted.

### Task 5: SQL presentation, handshake, and initial snapshot

**Files:**

- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/plugin.xml`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/MonacoSQLPresentation.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/EditorSessionFactory.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/DBeaverEditorAdapter.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/DBeaverEditorAdapterFactory.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/DBeaver26EditorAdapter.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/UnavailableMutationProbePort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/UnavailableUndoPort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/UnavailableCommandPort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/UnavailablePresentationPort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/port/DocumentPort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/port/SelectionPort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/port/SelectionPublishResult.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/port/UndoPort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/port/CommandPort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/port/PresentationPort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/port/MutationProbePort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/port/ProbeOpenResult.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/port/ProbeDocumentLease.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/presentation/EditorPresentation.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/presentation/EditorViewState.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/selection/MonacoSelectionProvider.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/sync/DBeaverDocumentFacade.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/DBeaverPublicApiContractTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/PresentationRegistrationTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/InitialSnapshotTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/SelectionProviderTest.java`
- Create: `web/tests/initialSnapshot.test.ts`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/pom.xml`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/META-INF/MANIFEST.MF`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/build.properties`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/pom.xml`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/META-INF/MANIFEST.MF`
- Modify: `web/src/bridge/BridgeClient.ts`
- Modify: `web/src/editor/createSqlEditor.ts`
- Modify: `web/src/main.ts`

**Interfaces:**

- Consumes: accepted SWT host, generated handshake/snapshot types, core session
  machine.
- Produces the `DBeaverEditorAdapter`, `DocumentPort`, `SelectionPort`,
  `UndoPort`, `CommandPort`, `PresentationPort`, `MutationProbePort`, and
  `ProbeDocumentLease` signatures fixed in
  `AGENTS.md`, plus an alternative presentation registered with ID
  `dbeaver.monaco.presentation`.

```java
public interface SelectionPort {
    PrimarySelection current();
    SelectionPublishResult publish(PrimarySelection selection);
}
public sealed interface SelectionPublishResult {
    record Published(SelectionAck acknowledgement)
        implements SelectionPublishResult {}
    record Rejected(FailureCode code) implements SelectionPublishResult {}
}
public interface UndoPort {
    boolean supportsCompoundChanges();
    CommandResult undo(RevisionBarrier barrier);
    CommandResult redo(RevisionBarrier barrier);
}
public interface PresentationPort {
    EditorPresentation current();
    CommandResult activate(EditorPresentation target,
                           EditorViewState viewState,
                           RevisionBarrier barrier);
}
public interface MutationProbePort {
    ProbeOpenResult openProbe();
}
public sealed interface ProbeOpenResult {
    record Opened(ProbeDocumentLease lease) implements ProbeOpenResult {}
    record Rejected(FailureCode code) implements ProbeOpenResult {}
}
public interface ProbeDocumentLease extends AutoCloseable {
    DocumentPort document();
    SelectionPort selection();
    UndoPort undo();
    @Override void close();
}
```

- [ ] **Step 1: Capture and test the pinned public API contract**

Use the resolved DBeaver 26.1.0 bundle, not `devel`, to compile a test asserting
that the extension class implements the exact public
`SQLEditorPresentation` methods and that `plugin.xml` resolves through
`org.jkiss.dbeaver.sqlPresentation`. Store only the public signatures used in
the compatibility test; do not copy DBeaver implementation source. The test
must also pin the public command IDs/services, `IDocumentExtension4`, compound
undo support, `ISelectionProvider`, and the presentation-switch mechanism
recorded by Task 1. Any missing or changed critical contract is a compile/test
failure, not a runtime version branch.

- [ ] **Step 2: Run the registration test and observe failure**

```bash
./mvnw -B -pl tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests \
  -am -Dtest=PresentationRegistrationTest verify
```

Expected: failure because the extension and class are absent.

- [ ] **Step 3: Implement the thin 26.1 adapter and presentation**

`MonacoSQLPresentation` delegates construction to `EditorSessionFactory`.
`DBeaver26EditorAdapter` is the root of a small adapter layer. Only it and the
explicit DBeaver/Eclipse port implementations it constructs may touch public
DBeaver editor objects. No core/bridge/web class, `.internal` import, or direct
`ExtraPresentationManager` reference is permitted.

At startup perform probes, load the page, handshake, send a full canonical
`DocumentSnapshot` stamped with the current readiness epoch, and wait for its
distinct web-to-host `SnapshotAck`. The web client applies the snapshot
through a non-undoing initialization path, verifies exact UTF-16 text, and
resets its drained edit/selection high-water marks to the snapshot's explicit
zero values. Only then does it acknowledge the exact
`(epoch, revision, documentStamp, resetEditSequence,
resetSelectionSequence)`;
`DocumentAck` is not valid for this direction. A missing, mismatched, or
delayed old-epoch acknowledgement is rejected and never records readiness.
Remain in read-only `SYNCING`; Task 5 records
`pendingSnapshotAcknowledgement` but leaves
`pendingRecoveryCheckpoint` and `currentDocument` empty.
Snapshot acknowledgement must never transition to `READY` or enable mutation.
Task 6 establishes recovery headroom and proves mutation/undo but remains
read-only; Task 7 owns the final command-channel readiness fact that may enable
editing.

Create all pure-core port interfaces with the exact signatures from
`AGENTS.md`; `DBeaverEditorAdapter` exposes each one. In this task
`DBeaverDocumentFacade.snapshot()` is active and tested, while
`apply(EditBatch)` returns typed `SESSION_NOT_READY` until Task 6 wires
incremental synchronization. `UnavailableMutationProbePort`,
`UnavailableUndoPort`, `UnavailableCommandPort`, and
`UnavailablePresentationPort` are non-null fail-closed implementations; every
mutating operation returns a typed `Rejected(SESSION_NOT_READY)` and no
capability probe treats them as success. The unavailable probe returns
`ProbeOpenResult.Rejected`; unavailable undo reports
`supportsCompoundChanges() == false`; and unavailable presentation reports
`Native` from `current()` while rejecting `activate(...)`.
`UnavailableCommandPort` explicitly rejects save, format, and execute; no
method is a placeholder success. Task 6 replaces the mutation/undo probe path,
Task 7 replaces live undo/commands, and Task 8 replaces presentation
activation.

- [ ] **Step 4: Implement primary selection publication**

`MonacoSelectionProvider` implements Eclipse `ISelectionProvider`, converts
UTF-16 offset/length to the canonical document selection, and sends standard
selection-change events. It rejects a stale revision/stamp or non-monotonic
`selectionSequence` through `SelectionPublishResult.Rejected` and returns
`Published(SelectionAck)` only after the canonical provider accepted the
update. Test listener registration/removal, acknowledgement, stable rejection
codes, stale updates, and out-of-range rejection.

- [ ] **Step 5: Run presentation verification**

```bash
./mvnw -B -pl tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests \
  -am verify
./mvnw -B verify
```

Expected: registration resolves, initial text/selection match `IDocument`,
the web test proves the exact snapshot is applied before `SnapshotAck`, and
Monaco remains read-only `SYNCING` even after that acknowledgement.
`pendingSnapshotAcknowledgement` is present but `currentDocument` remains
empty until Task 6 proves matching recovery headroom. It never reaches
editable `READY` in Task 5, and no `session.mode=EDITABLE` is sent.

- [ ] **Step 6: Commit and stop**

```bash
git add bundles tests web
git commit -m "feat: register Monaco SQL presentation"
```

Open the Task 5 draft PR. Do not add incremental edits or native execution.

### Task 6: Incremental two-model synchronization

**Files:**

- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/DocumentState.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/ApplyDecision.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/BarrierResult.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/CanonicalReconcileResult.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/ExternalCanonicalChange.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/ExternalChangeQueueLimits.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/InverseEditLog.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/sync/DocumentSyncEngine.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/recovery/RecoveryJournal.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/recovery/RecoveryCandidateStore.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/recovery/RecoveryEligibilityCalculator.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/recovery/JournalAppendResult.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/recovery/RecoveryEntryState.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/sync/DocumentSyncController.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/sync/EditOriginGuard.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/sync/ProjectionFlushCoordinator.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/sync/ProjectionRecoveryCapture.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/sync/ExternalCanonicalChangeQueue.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/MutationChannelProbe.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/DBeaverMutationProbePort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/ProbeDocumentLeaseImpl.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/ProbeUndoPort.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/tests/DocumentSyncProperties.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/tests/CircuitBreakerTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/tests/RecoveryJournalTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/tests/RecoveryEligibilityTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/tests/RecoveryCandidateStoreTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.jqwik.fixture/pom.xml`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.jqwik.fixture/META-INF/MANIFEST.MF`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.jqwik.fixture/build.properties`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.jqwik.fixture/about.html`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.jqwik.fixture/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/jqwikfixture/JqwikEngineFixture.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/CompoundDocumentApplyTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/MutationChannelProbeTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/SelectionBarrierTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/ProjectionFlushCoordinatorTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/ExternalCanonicalChangeQueueTest.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/bridge/mapping/BridgeMessageMapper.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/browser/BridgeFunction.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/EditorSessionFactory.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/MonacoSQLPresentation.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/sync/DBeaverDocumentFacade.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/DBeaverEditorAdapter.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/DBeaverEditorAdapterFactory.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/DBeaver26EditorAdapter.java`
- Modify: `pom.xml`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/pom.xml`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests/META-INF/MANIFEST.MF`
- Modify: `scripts/verify-test-target.sh`
- Modify: `web/src/bridge/BridgeClient.ts`
- Modify: `web/src/editor/createSqlEditor.ts`
- Modify: `web/src/main.ts`
- Create: `web/tests/documentSync.test.ts`

**Interfaces:**

- Consumes: canonical snapshot, document/selection ports, typed edit protocol.
- Produces:

```java
public record TextEdit(int offset, int length, String text) {}
public record EditBatch(long readinessEpoch, long baseRevision,
                        long baseDocumentStamp,
                        long clientSequence,
                        List<TextEdit> edits) {}
public final class DocumentSyncEngine {
    public ApplyDecision accept(DocumentState state, EditBatch batch);
}
public final class DocumentSyncController implements AutoCloseable {
    public ApplyResult applyMonaco(EditBatch batch);
    public CompletionStage<CanonicalReconcileResult> reconcileCanonicalChange(
        DocumentEvent event);
    public BarrierResult barrier(RevisionBarrier requested);
}
public final class ProjectionFlushCoordinator implements AutoCloseable {
    public CompletionStage<FlushBarrierResponse> freezeAndDrain(
        long readinessEpoch, FlushPurpose purpose);
    public enum FlushPurpose {
        EXTERNAL_CANONICAL_CHANGE, HOST_COMMAND,
        PRESENTATION_SWITCH, RESYNC_RECOVERY_CAPTURE
    }
}
public sealed interface CanonicalReconcileResult {
    record Patched(CanonicalPatchAck acknowledgement)
        implements CanonicalReconcileResult {}
    record RecoveryRequired(ReadinessStamp sourceStamp, FailureCode reason)
        implements CanonicalReconcileResult {}
    record Rejected(FailureCode code) implements CanonicalReconcileResult {}
}
public record ExternalCanonicalChange(
    ReadinessStamp before,
    ReadinessStamp after,
    int offset,
    String replacedText,
    String insertedText) {}
public record ExternalChangeQueueLimits(
    int maxEntries,
    long maxRetainedUtf16Bytes,
    long metadataBytesPerEntry) {
    public static final ExternalChangeQueueLimits DEFAULT =
        new ExternalChangeQueueLimits(256, 64L * 1024 * 1024, 4L * 1024);
}
public sealed interface BarrierResult {
    record Satisfied(long readinessEpoch, long revision, long documentStamp,
                     long editSequence,
                     long selectionSequence) implements BarrierResult {}
    record Rejected(FailureCode code) implements BarrierResult {}
}
public sealed interface JournalAppendResult {
    record Stored() implements JournalAppendResult {}
    record CapacityExceeded() implements JournalAppendResult {}
}
```

`CanonicalReconcileResult.RecoveryRequired` is deliberately pre-store. It
carries no text candidate, recovery handle, epoch increment, or permission to
send a snapshot. It only asks the owner to begin the correlated
`ProjectionRecoveryCapture`; the Task 2 exact `ResyncRecoveryStored` path is
the sole operation that may advance the resync transaction.

- [ ] **Step 1: Write failing property and compound-change tests**

Do not add jqwik to the Maven target: jqwik 1.9.3 jars do not provide OSGi
bundle metadata, so `missingManifest="error"` must reject them there. Instead,
add a test-only `eclipse-plugin` fixture before the core tests in the default
reactor. Its POM uses `maven-dependency-plugin:3.11.0` to copy exactly
`net.jqwik:jqwik-api:1.9.3` and `net.jqwik:jqwik-engine:1.9.3` into `lib/`,
lists both jars on its `Bundle-ClassPath`, exports only jqwik API packages to
test bundles, and retains the original EPL-2.0 notices and engine service
descriptor. Platform dependencies resolve from the Task 1 JUnit Platform
1.13.4 test target. `JqwikEngineFixture` asserts
`ServiceLoader<TestEngine>` discovers exactly jqwik 1.9.3 inside the installed
OSGi test runtime. Add the fixture requirement only to the core test manifest.
`verify-test-target.sh` proves the fixture, nested jars, and jqwik packages are
absent from the runtime feature and p2 repository.

Generate random insert/delete/replace batches including surrogate pairs,
overlapping-invalid ranges, multiple cursors, external canonical edits, stale
epochs/revisions/stamps, duplicate client sequences, selection races, and
canonical changes between validation and apply. Reject edits whose boundary
splits a UTF-16 surrogate pair. The invariant after every acknowledged batch
and satisfied barrier is equality of the two UTF-16 code-unit sequences.

Test that canonical patches do not enter Monaco's undo history, selection
acknowledgements are monotonic, and a command barrier rejects any unacknowledged
document revision, document stamp, or selection sequence. Test the circuit
breaker through first mismatch, successful resync, and second mismatch; no API
may reset it. Inject a failure after every possible edit in a multi-edit batch
and prove that inverse edits restore exact pre-batch text before fallback; the
dirty state may become conservatively dirty but must never become falsely
clean.

Test recovery limits at byte and entry `limit - 1`, `limit`, and `limit + 1`.
Prove deterministic UTF-8 wire-size accounting uses overflow-safe arithmetic;
a pending or failed entry is never evicted; acknowledged-prefix compaction
frees capacity; one oversized batch never mutates the canonical document or
receives an acknowledgement; a 10 MiB export fits; and over-limit recovery
text is rejected without truncation. Prove the 64 KiB metadata bound against
all maximum-length schema metadata, and test the exact recovery-eligibility
formula at `limit - 1`, `limit`, and `limit + 1`. A 10 MiB ASCII checkpoint
must be eligible; a legal but worst-case escaped 10 Mi-code-unit checkpoint
must remain protocol-valid while edit-ineligible. External canonical growth
and post-ack compaction must revoke eligibility before another host edit is
accepted. After several successful edits, prove `DocumentReadinessAdvanced`
keeps the session editable at each new stamp without replaying startup probes.
After a resync that deliberately reuses the same revision/stamp numbers,
inject every delayed old-epoch ack/readiness/loss event and prove none changes
the new epoch. For external canonical changes, cover an empty queue, an
already-created undelivered edit, an unacknowledged selection, flush timeout,
and a change whose retained pre-state no longer matches. Incremental patching
is allowed only in the empty/exact-prestate case; conflicting Browser text is
reported as a recovery candidate before resync/fallback. Assert
`reconcileCanonicalChange(...)` returns an incomplete `CompletionStage`
promptly from the SWT listener call, never waits for JavaScript there, and
completes only after flush/patch acknowledgement or typed failure. Queue
several ordered external events while the first flush is pending; the
controller serializes every event, never drops text, and either applies each
exact pre/post transition or converts the retained sequence into one full
resync/recovery transaction. A bounded queue overflow fails closed rather than
coalescing away an edit.

- [ ] **Step 2: Observe focused failure**

```bash
./mvnw -B -pl tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests,\
tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests -am verify
```

Expected: failure because synchronization classes are absent.

- [ ] **Step 3: Implement pure synchronization decisions**

Validate readiness epoch, base revision, client sequence monotonicity,
non-negative ranges, base document stamp, non-overlap, document bounds, and
surrogate boundaries. Reject an old epoch with
`STALE_READINESS_EPOCH`; return a typed resync decision on stale revision or
stamp. Sort accepted edits by descending offset without mutating the input
list. `BarrierResult` compares the exact
`(epoch, revision, documentStamp, editSequence, selectionSequence)` and never
waits or blocks the SWT thread.

- [ ] **Step 4: Apply accepted edits through Eclipse**

On the SWT UI thread, wrap the descending replacements with
`beginCompoundChange()`/`endCompoundChange()` in `try/finally`. Use an origin
token so resulting `IDocument` events are not echoed. External events produce
stamped canonical patches. Apply those patches in Monaco with a listener
suppression token and the non-undoing model API; never call
`pushEditOperations` for canonical changes.

Before mutation, capture each replaced substring in an `InverseEditLog`.
If an expected document exception occurs after a partial multi-edit, apply only
the completed inverses in reverse operation order and verify exact pre-batch
UTF-16 text before exposing Native. If verification fails, freeze both plugin
mutation paths and present canonical/recovery comparison; never claim a clean
fallback. Do not catch `OutOfMemoryError` or broad `Throwable`.

Before the first canonical replacement, atomically reserve space and append
each size-, schema-, and synchronization-semantic-validated batch to the
host-side `RecoveryJournal`, then mark it acknowledged or failed. The journal
uses Task 2 `RecoveryLimits`, owns a bounded host-known checkpoint, may compact
an acknowledged prefix, and never evicts pending or failed entries. If
reservation cannot fit the batch after safe compaction, return
`RECOVERY_CAPACITY_EXCEEDED`, leave `IDocument` byte-for-byte unchanged, freeze
Monaco read-only, and enter explicit export/Native recovery. Never truncate
SQL. The journal survives Browser disposal but not a JVM crash and never
contains connection metadata. It cannot recover a keystroke that JavaScript
never delivered. Enforce the parent-owned `CircuitBreaker`: one full canonical
resync is allowed for the SQL-editor lifetime; a later mismatch disables
Monaco, including after reactivation.

For initial startup or a full resync, use `RecoveryEligibilityCalculator` to
encode the canonical checkpoint with the same deterministic accounting as the
journal before emitting `RecoveryCheckpointReady` for the exact current
`ReadinessStamp`:

```text
checkpointWireBytes
  + ProtocolLimits.MAX_EDIT_BATCH_UTF8_BYTES
  + RecoveryLimits.MAX_JOURNAL_ENTRY_METADATA_UTF8_BYTES
  <= RecoveryLimits.DEFAULT.maxJournalWireBytes()
```

During editable operation, do not emit startup readiness events again.
After each successful Monaco edit, compute eligibility, create the
host-to-web `DocumentAck`, and atomically emit
`DocumentReadinessAdvanced(newStamp, acknowledgedClientSequence,
recoveryEligible)` in `READY` or `DEGRADED`. The edit originated in the
already matching web model, so this advances the current document fact without
invalidating same-epoch mutation or guard facts.

For an external canonical change, `documentAboutToBeChanged` computes an
overflow-safe reservation before copying retained text. The queued immutable
`ExternalCanonicalChange` stores the exact replaced/inserted segments plus
pre/post stamps, not two whole-document snapshots. Its conservative retained
size is
`2 * (replacedText.length + insertedText.length) + metadataBytesPerEntry`,
with checked multiplication/addition. The shared queue reserves both one entry
and those bytes atomically, then the post-change callback completes and
enqueues it in order and returns its `CompletionStage` immediately.

The controller allows at most 256 pending events and at most 64 MiB of
aggregate retained UTF-16 bytes/metadata. Neither limit implies the other. A
failed count or byte reservation freezes the projection and returns
`RecoveryRequired` to begin correlated capture/resync; it does not retain a
partial event, drop/coalesce text, or claim resync is scheduled. The already
canonical external change remains authoritative. Tests cover exactly-at-limit,
count overflow, byte overflow with fewer than 256 large replacements,
arithmetic overflow, reservation rollback, and release-on-dequeue/disposal.
They assert retained accounting returns to zero and that 256 × 10 MiB can
never be allocated.

The serialized asynchronous worker sets web mode to `READ_ONLY` and uses
`ProjectionFlushCoordinator` before sending the patch. The correlated flush
must prove the web projection was at the exact pre-change barrier and that no
edit or selection message remains dispatched-but-unacknowledged. Only then
send the current-epoch `CanonicalPatch` and wait for the distinct matching
web-to-host `CanonicalPatchAck` before advancing document readiness or
re-enabling input. That advancement retains the exact acknowledged edit
sequence proven by the pre-change flush; it does not invent or reset it.

If a Browser-local edit was already queued when the native change occurred,
its old-base apply will conflict with the new canonical state. Do not apply the
incremental patch or declare the Browser text lost: reject the stale batch,
retain/export its honest projection candidate, and enter the one permitted
full resync or explicit recovery/fallback. The web applies a safe patch
through the non-undoing path, verifies exact UTF-16 text, and then
acknowledges. A mismatched or stale-epoch ack is ignored/rejected. Recompute
eligibility after that acknowledgement and after every compaction.

Every automatic full resync, regardless of mismatch source, first uses
`ProjectionRecoveryCapture` under the source epoch. It freezes, attempts the
typed drain, requests bounded `recovery.export`, validates exact text and
high-water metadata, and commits the candidate to the volatile
`RecoveryCandidateStore` under the current activation/resync/source/request
tuple, receiving an opaque handle. Only then may the
session emit the fully correlated `ResyncRecoveryStored`, enter
`PreparingSnapshot`, increment the epoch, and request the authorized canonical
snapshot capture. If the Browser cannot export or
validation/limits fail, keep the projection read-only and offer explicit
host-journal/Native recovery; never overwrite the only live copy of
Browser-local text.

Task 6 wires `BridgeClient.onRecoveryExportRequest` and
`respondToRecoveryExport`. The web listener synchronously sets the editor
read-only before reading the model, validates source epoch and correlation,
captures exact UTF-16 text plus dispatched/acknowledged edit and selection
high-water marks, and returns the typed bounded response. Tests cover wrong
epoch/recovery sequence/correlation, a delayed or duplicate response, an edit
created just before freeze, over-limit text, injected candidate-store failure,
and disposal during capture. No failure emits `ResyncRecoveryStored` or a
snapshot send.

Every `DocumentAck` reports the result in `recoveryEligible`. A false result,
or current-stamp `RecoveryHeadroomLost`, sends
`session.mode=READ_ONLY`, rejects further local input, and enters explicit
recovery/fallback with `RECOVERY_CAPACITY_EXCEEDED`. Delayed loss from an
older epoch is a no-op. Queued Browser-only text remains exportable with honest
provenance. This eligibility gate never replaces the atomic reservation
before each canonical mutation.

- [ ] **Step 5: Prove mutation and compound undo before enabling editing**

Replace the Task 5 unavailable probe with `DBeaverMutationProbePort`.
`openProbe()` returns `ProbeOpenResult.Opened` with an idempotently disposable
`ProbeDocumentLeaseImpl`
owning a distinct hidden JFace document/viewer/rewrite target/undo manager and
the same concrete document/selection/undo factories used by the live adapter.
`MutationChannelProbe` sends a stamped synthetic surrogate-pair multi-edit
through the real Browser bridge, observes the canonical event/ack, performs
compound undo through `ProbeUndoPort`, and verifies the original UTF-16
sequence. It must never mutate the user's document identity, text, stamp,
dirty state, listeners, or undo history. Timeout, missing compound undo, leak,
or mismatch is a critical failure and leaves Native usable.

Only this successful probe emits
`MutationChannelReady(currentReadinessEpoch)`. The proof is bound to the epoch,
not the user's document revision. The session records it, but
`currentDocument` still requires the exact matching snapshot acknowledgement
and recovery checkpoint. The model remains read-only `SYNCING`; Task 7 has not
yet proven the command channel. A resync clears the proof and requires a new
current-epoch probe result; a delayed prior result cannot combine.

- [ ] **Step 6: Run synchronization verification**

```bash
./mvnw -B -pl tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests,\
tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests -am verify
npm --prefix web test
./mvnw -B verify
bash scripts/verify-test-target.sh repository/target/repository
```

Expected: property tests complete without divergence, one Monaco event is one
Eclipse compound operation, the full
epoch/revision/stamp/edit-sequence/selection-sequence barrier is enforced, the
resync allowance cannot reset, recovery overflow cannot mutate the document,
checkpoint/headroom eligibility gates input before known exhaustion, and a
successful throwaway mutation/undo probe still leaves the visible model
read-only in `SYNCING`.

- [ ] **Step 7: Commit and stop**

```bash
git add pom.xml bundles scripts tests web
git commit -m "feat: synchronize Monaco with canonical document"
```

Open the Task 6 draft PR.

### Task 7: Eclipse-authoritative undo and native commands

**Files:**

- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/command/EclipseUndoPort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/command/DBeaverCommandPort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/command/CommandRouter.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/command/MonacoCommandGuard.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/command/NativeCommandTransaction.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/CommandChannelProbe.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/UndoRoutingTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/CommandRouterTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/NativeCommandSurfaceBarrierTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/CommandChannelProbeTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.h2.fixture/pom.xml`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.h2.fixture/META-INF/MANIFEST.MF`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.h2.fixture/build.properties`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.h2.fixture/about.html`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.e2e.tests/pom.xml`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.e2e.tests/META-INF/MANIFEST.MF`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.e2e.tests/build.properties`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.e2e.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/e2e/NativeCommandE2ETest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.e2e.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/e2e/H2TestConnection.java`
- Create: `.github/workflows/native-e2e.yml`
- Modify: `pom.xml`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/browser/BridgeFunction.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/sync/ProjectionFlushCoordinator.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/DBeaver26EditorAdapter.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/EditorSessionFactory.java`
- Modify: `web/src/bridge/BridgeClient.ts`
- Modify: `web/src/bridge/HostCommand.ts`
- Create: `web/src/bridge/CommandBarrier.ts`
- Modify: `web/src/editor/createSqlEditor.ts`
- Modify: `web/src/main.ts`
- Create: `web/tests/hostCommands.test.ts`

**Interfaces:**

- Consumes: synchronized document revision, primary selection provider, public
  DBeaver command service, and the Task 2 `EditorCommand`, `ExecuteRequest`,
  `RevisionBarrier`, and `CommandResult` value types.
- Produces:

```java
public final class CommandRouter {
    public CompletionStage<EditorCommandResponse> dispatch(
        EditorCommandRequest request);
}
```

`dispatch` validates and enqueues, then returns an incomplete stage promptly;
it never waits for the Browser on the SWT thread. The bridge replies to the
original correlation only when the stage completes. Native guard intents use
the same asynchronous dispatcher.

- [ ] **Step 1: Write failing undo and command tests**

Test that every supported Monaco undo/redo surface invokes Eclipse exactly
once, changes canonical text, and causes the canonical document listener to
emit a patch that is excluded from Monaco undo history. Cover `Ctrl/Cmd+Z`,
redo keys, custom context menu, custom command palette, and every programmatic
command exposed by the web facade. Disable Monaco's built-in context
menu/quick-command surfaces so they cannot bypass the host route; do not expose
the raw editor command service.

Test command rejection for stale revision, stale stamp, unacknowledged
epoch/edit sequence/selection sequence, out-of-range selection, and any
non-editable session.
Before `CommandChannelReady`, prove the visible model remains read-only and
toolbar/menu/global commands reject without reaching a native handler. After
snapshot acknowledgement plus recovery readiness, mutation readiness, and
command readiness, prove exactly one `EnableEditing` effect and command-capable
`READY`/optional-only `DEGRADED`. Unknown wire command kinds
remain a Task 2 schema/decoder test because a Java sealed router cannot receive
one. Exercise DBeaver toolbar, menu, and global keybinding entry points and
prove none can bypass the same barrier.

Exercise readiness in the order `CommandChannelReady` first, then exact
`CommandChannelLost`, then all other facts. The session must fail closed and
must never edit. During a full resync, assert that the existing physical guard
enters blocking mode before asynchronous recovery starts, its old logical
lease is revoked, no second Eclipse handler activation is installed, and only
an explicit successful current-epoch rebind emits a new lease/readiness event.
Cover rebind failure, stale old-lease loss, duplicate rebind, and disposal.

For both web-origin and native-surface commands, inject an already-created but
undelivered edit and selection event. Prove the transaction first freezes the
model, drains both queues, receives a correlated current-epoch flush response,
and invokes the native handler only when dispatched and acknowledged
sequences plus the full controller barrier match. Cover timeout, late local
event after freeze, duplicate response, stale epoch, wrong correlation UUID,
and mismatched sequence; all reject with `FLUSH_BARRIER_FAILED` and never
invoke native code. No test may simulate safety by pre-draining the queue.
Assert `CommandRouter.dispatch(...)` returns promptly while the flush future
is unresolved and that a synchronous `BrowserFunction` only
validates/enqueues; completion and `command.response` occur later.
Retry the exact same web command request after a lost response and prove the
cached response is returned while the original save/undo/redo/format/execute
handler invocation count remains one. Reuse the sequence or message ID with
different command content and prove it is rejected.

Exercise any native format toolbar/menu/global-keybinding surface captured by
Task 1. If present, prove it enters the same flush and revision barrier and its
canonical patch is acknowledged before editing resumes. If no format surface
was captured, prove the typed `Format` command returns
`COMMAND_UNAVAILABLE` and the optional UI action is disabled. If a mutating
format surface exists but cannot be guarded, command readiness must fail
critically.

- [ ] **Step 2: Observe focused failure**

```bash
./mvnw -B -pl tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests \
  -am -Dtest=UndoRoutingTest,CommandRouterTest verify
npm --prefix web test
```

Expected: failure because the real command ports, router, guard, and probe are
absent; Task 5's unavailable ports remain fail-closed.

- [ ] **Step 3: Implement Eclipse-only undo and redo**

Intercept Monaco keybindings, call the editor's public Eclipse undo manager,
custom menu/palette commands, and web-facade programmatic calls; route each to
the shared flush transaction and then `UndoPort`; let the resulting canonical
event update Monaco. Never call Monaco's independent undo stack after session
readiness. Canonical patches must use the non-undoing model path established
in Task 6 and receive `CanonicalPatchAck` before input is restored.

- [ ] **Step 4: Implement the closed native command router**

Map only `Save`, `Undo`, `Redo`, `Format`, and `Execute` sealed types. Resolve
and invoke the public DBeaver/Eclipse commands verified against the pinned
26.1.0 target.
The adapter maps statement and script execution to
`SQLEditorCommands.CMD_EXECUTE_STATEMENT` and
`SQLEditorCommands.CMD_EXECUTE_SCRIPT`; save/undo/redo use the exact public
Eclipse IDs captured in Task 1. `Format` reuses only the captured native
formatter command; the plugin does not implement formatting logic. Check
defined/enabled state and the complete
epoch/revision/stamp/edit-sequence/selection-sequence barrier before
invocation. JavaScript sees only the closed command union, never a raw command
ID.

While Monaco is active, `MonacoCommandGuard` owns higher-priority Eclipse
handler activations for the native save/undo/redo/statement/script command IDs
and for a discovered format ID. DBeaver toolbar, menu, and global-keybinding
invocations enter the same `NativeCommandTransaction`; web command requests
enter that transaction too.

There is exactly one physical `MonacoCommandGuard` activation per Monaco
activation. It has explicit `BLOCKING`, `ACTIVE`, and `DISPOSED` modes. Initial
probing installs it once. Entering resync synchronously changes that same
activation to `BLOCKING`, rejects every intercepted surface, and revokes the
old logical `CommandGuardLease`; removing the activation during this gap is
forbidden because it would expose unguarded native handlers. After the new
snapshot/recovery/mutation evidence is current, `CommandChannelProbe` rechecks
the handler ownership and atomically rebinds the same physical activation to a
fresh target-epoch lease UUID. Only that rebind emits
`CommandChannelReady(targetEpoch, newLeaseId)`. Failure disposes it and fails
closed. Switching/fallback/editor close disposes it exactly once.

Before starting a transaction, route the typed request through Task 2's
per-origin/per-epoch `CommandReplayLedger`. An exact completed retry returns
its cached full `EditorCommandResponse`, including the exact applied barrier;
no flush or native handler runs again. `ReplayDecision.Start` returns the
single-use `CommandCompletionPermit`; only that permit/request pair may
complete and cache the full response. Completing with only `CommandResult`, a
wrong permit, or a reconstructed barrier is forbidden. Native surface
invocations receive a host-allocated monotonic sequence in the separate
`NATIVE` namespace; they never alter the web high-water mark.

The transaction sends `session.mode=READ_ONLY`, then a correlated
`barrier.flush.request`. Task 6's `ProjectionFlushCoordinator` never blocks
the SWT UI thread: it waits asynchronously for the web client to freeze,
drain all document/selection messages, and return `barrier.flush.response`. It validates
the exact epoch, UUID, dispatched-versus-acknowledged edit and selection
sequences, and current controller barrier. Only then, on the SWT thread, the
guard temporarily deactivates its own handler activation, invokes the original
public DBeaver/Eclipse handler, and restores the guard in `finally` with a
reentrancy token. After any resulting canonical patch acknowledgement, the
host sends `session.mode=EDITABLE` only if all current readiness facts still
hold. On timeout or stale state it keeps read-only and rejects without
invoking the original handler.

Task 1's API evidence must confirm every claimed native surface is
command-backed. If no format surface exists, `Format` is optional and disabled
with `COMMAND_UNAVAILABLE`. If a format surface exists but its handler cannot
be guarded, Task 7 stops with `COMMAND_GUARD_UNAVAILABLE`; it cannot leave an
unguarded canonical mutation path.

`CommandChannelProbe` first uses a separate probe-owned guard to prove without
executing SQL or saving user data that all five critical public command
definitions resolve, original handlers can be located, scoped activations own
the expected editor context, a dry-run stale flush/barrier cannot reach a
handler, and disposal removes every probe activation. It tests the optional
format definition/surfaces according to the rule above. It then installs and
verifies the distinct live editor guard with a unique lease UUID. Emit
`CommandChannelReady(currentEpoch, leaseId)` only while that exact guard
remains installed; do not dispose it as part of the probe. Losing a critical
definition, original handler, or that live activation immediately emits
`CommandChannelLost(currentEpoch, leaseId)` and a critical
`ProbeFailed(COMMAND_GUARD_UNAVAILABLE)`, including while the reducer is still
`SYNCING`. Post-resync proof uses the atomic same-activation rebind above,
never another live handler activation. The session reducer sends the only
production `session.mode=EDITABLE` after current document, mutation, and
command readiness are all present.

- [ ] **Step 5: Add a real DBeaver product end-to-end harness**

Keep the E2E module out of the default reactor. Add a root `native-e2e` profile
whose only extra modules, in order, are the Task 4 native test target, H2
fixture, and E2E test plugin. The E2E module selects that target and inherits
the same enforced absolute `dbeaver.product.path`, JUnit 5 provider,
`failIfNoTests`, UI harness/thread, and verified product/application settings.
The fixture is an `eclipse-plugin` that uses
`maven-dependency-plugin:3.11.0` to copy only
`com.h2database:h2:2.4.240` into `lib/h2-2.4.240.jar`, declares it on
`Bundle-ClassPath`, retains H2's license notice, and exposes it only to the E2E
test manifest. Add an installed-resolution assertion. Neither fixture nor H2
may appear in the runtime feature or repository.

`H2TestConnection` owns a unique in-memory URL and the complete temporary
DBeaver driver/data-source lifecycle: registration, open connection, close,
registry removal, and idempotent cleanup. Failure-path tests prove no driver,
data source, connection, editor input, or workspace state survives.
`NativeCommandE2ETest` owns the editor, command, result-grid, and
no-plugin-JDBC assertions; the fixture itself owns only the jar, OSGi metadata,
and retained license.

Use the Tycho UI harness against the checksum-pinned DBeaver product. Create a
deterministic in-memory connection through DBeaver's connection registry, open
a real SQL editor, select `SELECT 42 AS answer`, invoke the Monaco
`Ctrl+Enter` route, and wait for DBeaver's native results controller/grid.
Assert the displayed column and value, current editor/document identity, and
absence of any plugin JDBC execution path. Repeat execution through the actual
DBeaver toolbar and menu after injecting an already-created but undelivered
edit and selection update; assert that the web model freezes, both queues
drain, and only the acknowledged intended SQL executes. Exercise native
save/undo/redo surfaces the same way. If Task 1 found a native format surface,
exercise it and assert barrier-before-format plus patch-ack-before-unlock.

`native-e2e.yml` uses `ubuntu-24.04`, pins every third-party action to a full
commit SHA, prepares the allowlisted Linux product, and runs the following
under a real display on the PR:

```bash
./mvnw -B -Pnative-e2e \
  -Ddbeaver.product.path="${DBEAVER_PRODUCT_PATH}" verify
```

Default `./mvnw verify` discovers no E2E or H2 fixture module and contains no
skipped/disabled native tests. The workflow uploads JUnit, DBeaver error log,
and a screenshot only on failure; test fixtures contain no external
credentials.

- [ ] **Step 6: Run command and end-to-end verification**

```bash
./mvnw -B verify
npm --prefix web run lint
npm --prefix web test
npm --prefix web exec -- playwright install --with-deps chromium
npm --prefix web exec -- playwright test
./mvnw -B -Pnative-e2e \
  -Ddbeaver.product.path=/absolute/verified/dbeaver-product verify
```

Expected: save and execute see canonical current text; Ctrl+Enter executes the
primary selection and uses the native result grid; compound multi-cursor edits
undo in one action; `CommandChannelReady` enables editing only after all
critical readiness facts exist; and the H2 fixture is absent from shipped p2
metadata.

- [ ] **Step 7: Commit and stop**

```bash
git add pom.xml bundles tests web .github/workflows/native-e2e.yml
git commit -m "feat: route undo save and SQL execution to DBeaver"
```

Open the Task 7 draft PR.

### Task 8: Bidirectional presentation switching and safe native fallback

**Files:**

- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/DBeaverPresentationPort.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/PresentationSwitchController.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/PresentationSwitchGate.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/SwitchPermit.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/PresentationViewStateStore.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/EditorLifetimeOwner.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/MonacoActivation.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/lifecycle/SqlEditorLifetimeState.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/presentation/SwitchPhase.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/presentation/SwitchTransaction.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/PresentationSwitchControllerTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/NativeFallbackTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/EditorLifetimeOwnershipTest.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/DBeaver26EditorAdapter.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/EditorSessionFactory.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/MonacoSQLPresentation.java`
- Modify: `web/src/bridge/BridgeClient.ts`
- Modify: `web/src/main.ts`
- Create: `web/tests/presentationSwitch.test.ts`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.e2e.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/e2e/NativeCommandE2ETest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.e2e.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/e2e/NativePresentationHandlerE2ETest.java`

**Interfaces:**

- Consumes: `PresentationPort`, canonical document/selection barrier, web
  flush acknowledgements, and the exact public presentation-switch contract
  proved in Task 1.
- Produces one controller that owns both directions; no recovery or UI class
  may call a DBeaver presentation manager directly.

Two lifetimes are explicit:

- the **SQL-editor lifetime** starts when the DBeaver SQL editor/document opens
  and ends only when that editor closes. `EditorLifetimeOwner` owns the latest
  immutable `CircuitBreaker` value, recovery store, journal/checkpoint,
  unresolved recovery material, and saved view state;
- a **Monaco activation** starts on each Native→Monaco attempt and ends on a
  confirmed Native switch, fatal fallback, failed activation, or editor close.
  It owns one fresh `AssetServerLease`, Browser/widget, bridge session/token,
  readiness-epoch/replay state, listeners, projection controllers, and exactly
  one physical command guard.

Only `LoopbackAssetServer` itself is process-scoped. A lease is never
process-scoped or reused. A new Monaco activation starts at readiness epoch
`1` but receives the SQL-editor lifetime's current breaker value; reducer
updates are written back to that parent before activation disposal. Switching
away and back therefore cannot replenish the one-resync allowance.

```java
public final class PresentationSwitchController {
    public CommandResult activateMonaco(EditorViewState requested);
    public CommandResult activateNative(EditorViewState requested);
    public CommandResult fallBackToNative(FailureCode cause);
}
public enum SwitchPhase {
    IDLE, FREEZING_SOURCE, VERIFYING_BARRIER,
    ACTIVATING_TARGET, RESTORING_VIEW, FAILED
}
```

- [ ] **Step 1: Write failing bidirectional switch tests**

Cover Native→Monaco and Monaco→Native with dirty and clean documents, empty
and non-empty selections, stale barriers, focus changes, scroll/view-state
restore, Browser failure, and repeated idempotent requests. Invoke both plugin
actions and DBeaver's actual presentation toolbar/menu/handler entry point.
Assert that only one presentation can accept edits outside the explicit
`SwitchPhase`, the canonical `IDocument` object never changes, and no
selection/text is silently discarded.

For both synchronous presentation hooks, assert the first external request
returns `false` quickly, sends current-epoch `session.mode=READ_ONLY`, and
schedules exactly one transaction through Task 6's
`ProjectionFlushCoordinator`. Inject undelivered edit and selection events and
prove the correlated typed flush drains both before the matching callback
consumes one session/target-bound permit and returns `true`; replay, wrong
target/session/epoch, and third callback fail. Repeated clicks coalesce, stale
async completions are ignored, barrier failure never invokes
`PresentationPort`, and Browser/guard disposal occurs only after confirmed
Native activation. Switch back to Monaco and prove a new bridge/session/guard
identity, fresh `AssetServerLease`/token, and fresh readiness probes are used;
only immutable view state, editor-lifetime breaker/recovery ownership, and the
process-scoped asset-server service may be reused. The old lease URI/token must
already be invalid.

Add ownership tests for clean switch-away/back, switch failure, fatal Browser
fallback with unresolved Browser-only text, explicit recovery
copy/download/discard, and SQL-editor close. Assert one live activation, one
physical guard, and one lease at a time; no activation disposal resets the
breaker or destroys unresolved recovery data.

- [ ] **Step 2: Observe focused failure**

```bash
./mvnw -B -pl tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests \
  -am -Dtest=PresentationSwitchControllerTest,NativeFallbackTest verify
npm --prefix web test
```

Expected: failure because the switch controller and DBeaver-facing port are
not implemented.

- [ ] **Step 3: Implement Native to Monaco switching**

Capture canonical revision/stamp, dirty state, primary selection, focus, and
view state. A successful prior Monaco→Native switch disposed its Browser,
guard, bridge, and readiness session, so Native→Monaco always creates a new
Monaco activation with epoch `1`, acquires a fresh lease from the reused
process-scoped server, and reruns all readiness probes. Initialize its context
with the editor-lifetime breaker value and recovery owner. Reuse only immutable
saved view state and those explicit parent-owned values; never reuse a disposed
lease, bridge, guard, or activation state. Send a full snapshot, restore only
range-valid view state, and activate `MonacoSelectionProvider`. Monaco remains
read-only until all Task 7 critical readiness gates pass. A failed gate leaves
Native active and focused and releases the new activation resources.

- [ ] **Step 4: Implement Monaco to Native switching**

Use the same `barrier.flush.request`/`barrier.flush.response` transaction as
native commands; do not create a second flush protocol. The web side
synchronously stops accepting edits, drains and awaits document and selection
acknowledgements, and reports the complete epoch/revision/stamp/edit/selection
barrier. Invoke only the public presentation mechanism captured in Task 1 through
`DBeaverPresentationPort`: the 26.1 adapter calls
`SQLEditor.showExtraPresentation("dbeaver.monaco.presentation")` for Monaco and
the public nullable-descriptor overload for Native. Restore canonical
selection/focus and dispose the Browser session after successful activation.
Never import or reflectively invoke `ExtraPresentationManager`.

Implement `MonacoSQLPresentation.canHidePresentation()` and
`canShowPresentation()` through `PresentationSwitchGate`. Without an internal
permit, either hook freezes/queues the controller transaction and immediately
vetoes by returning `false`; it never waits for JavaScript on the SWT thread.
After successful flush/readiness/barrier work, the controller arms a private
one-shot permit bound to session, target, and activation, calls
`PresentationPort.activate(...)`, and clears the permit in `finally`. The
re-entered hook atomically consumes it. A typed canonical-fallback permit may
be created only after an explicit user fallback or critical Browser failure;
it never masquerades as a satisfied revision barrier.

If the barrier fails while the Browser is alive, offer three explicit
outcomes: retry synchronization, export the current projection through the
typed `recovery.export` request, or explicitly switch to Native using the
canonical document after acknowledging any uncommitted projection risk.
Automatic fallback after a critical bridge/browser failure switches to Native
using the canonical document. Before disposing the activation, transfer the
bounded host journal/checkpoint and any committed Browser candidate to
`EditorLifetimeOwner`; activation disposal never destroys unresolved recovery
material. A clean switch may release fully acknowledged activation entries
only after proving there is no unresolved projection candidate.

- [ ] **Step 5: Run unit and real-product switching verification**

```bash
./mvnw -B verify
npm --prefix web test
./mvnw -B -Pnative-e2e \
  -Ddbeaver.product.path=/absolute/verified/dbeaver-product verify
```

Expected: the real DBeaver product switches in both directions, retains
canonical text/dirty state/selection, restores focus, and automatically
returns to a usable Native presentation after an injected critical failure.
The E2E must exercise DBeaver's native switch handler; a controller-only test
does not satisfy this gate.

- [ ] **Step 6: Commit and stop**

```bash
git add bundles tests web
git commit -m "feat: switch safely between native and Monaco presentations"
```

Open the Task 8 draft PR.

### Task 9: Recovery, diagnostics, performance, and leak hardening

**Files:**

- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/capability/CapabilityStatus.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/core/diagnostic/LatencySummary.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/compatibility/CompatibilityReport.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/RecoveryController.java`
- Create: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/lifecycle/SessionRegistry.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/RecoveryControllerTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/SessionLeakTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/tests/SensitiveLoggingTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.performance.tests/pom.xml`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.performance.tests/META-INF/MANIFEST.MF`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.performance.tests/build.properties`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.performance.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/performance/PerformanceBudgetTest.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.performance.tests/fixtures/sql-1MiB.sql`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.performance.tests/fixtures/sql-10MiB.sql`
- Create: `web/tests/largeDocument.spec.ts`
- Create: `.github/workflows/performance.yml`
- Create: `docs/evidence/task-9-performance.md`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/MonacoSQLPresentation.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/presentation/PresentationSwitchController.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/browser/SwtBrowserHost.java`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/ui/sync/DocumentSyncController.java`
- Modify: `web/src/bridge/BridgeClient.ts`
- Modify: `web/src/main.ts`
- Modify: `pom.xml`

**Interfaces:**

- Consumes: host-side `RecoveryJournal`, typed recovery-export messages,
  presentation switch controller, session state machine, and disposable scope.
- Produces:

```java
public record CompatibilityReport(
    String pluginVersion, String dbeaverVersion, String eclipseVersion,
    String javaVersion, String os, String browser, String adapterId,
    int protocolMajor, int protocolMinor,
    Map<Capability, CapabilityStatus> capabilities,
    List<FailureCode> failures,
    Map<String, LatencySummary> latency,
    long resyncAttempts, long breakerTransitions,
    long bridgeMessagesReceived, long bridgeMessagesRejected) {}
```

- [ ] **Step 1: Write failing recovery, privacy, and lifecycle tests**

Test Browser crash before delivery, after Java validation, during canonical
apply, and after acknowledgement; live-Browser export; protocol mismatch;
adapter `LinkageError`; idempotent disposal; 100 open/close cycles; and
diagnostics/log capture containing no known SQL, credential, token, connection
URL, local path, or database-object sentinel. Explicitly prove that a
keystroke never delivered by JavaScript is reported as unrecoverable. Separate
Monaco-activation close from SQL-editor-lifetime close: fatal fallback and
switch-away retain unresolved candidates, switch-back cannot reset the
breaker, explicit resolution wipes selected material, and editor close wipes
all remaining bounded recovery buffers.

Add the deterministic 1 MiB and 10 MiB SQL fixtures at the exact module paths
listed above. Measure cold initial sync,
edit acknowledgement, selection acknowledgement, canonical patch, scroll
frame, and disposal. Collect count, median, p95, and p99 rather than a single
best-case sample. The Java latency measurements must traverse the installed
plugin's real
`Monaco → SWT BrowserFunction → DocumentSyncController → IDocument → ack/patch`
path in the checksum-pinned DBeaver product; a mock bridge does not satisfy a
budget. Standalone Playwright owns only render/scroll-frame measurements.

- [ ] **Step 2: Observe focused failure**

```bash
./mvnw -B -pl tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests,\
tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui.tests -am verify
```

Expected: failure because recovery and diagnostic types are absent.

- [ ] **Step 3: Implement honest bounded recovery and fallback**

Freeze Monaco on fatal mismatch. If the Browser is alive, request and validate
an explicit `recovery.export.response` containing revision/stamp and projection
text. Independently reconstruct the best host-known candidate from the last
canonical snapshot plus validated journal entries. Label each candidate with
its source and last acknowledged sequence; never imply that undelivered
keystrokes can be recovered.

After a Browser crash, use only the host journal and canonical document. Make
the candidate explicitly copyable/downloadable, then switch through
`PresentationSwitchController` or keep Monaco read-only. Never auto-apply
recovery text to `IDocument`. Reuse the protocol kinds, stable failures, and
Task 2/6 byte, text, and entry limits without changing the schema. Zero the
journal and candidate buffers only after explicit user discard or a confirmed
copy/download resolution, and always on SQL-editor-lifetime close. Monaco
activation disposal alone must transfer and retain unresolved material in
`EditorLifetimeOwner`; it may erase only entries proven fully acknowledged
with no unresolved projection candidate. Never persist recovery outside the
process without a separate future ADR.

Catch `LinkageError` only around adapter loading/probing and convert it to
`INCOMPATIBLE_DBEAVER_API`. Do not catch `OutOfMemoryError` or broad
`Throwable`.

- [ ] **Step 4: Implement privacy-safe compatibility reporting**

Include versions, capabilities, stable codes, latency aggregates, resync count,
breaker transitions, and message accept/reject counts. Define
`CapabilityStatus` as a closed value containing enabled/disabled, criticality,
and a stable reason code only. Exclude SQL, arbitrary exception messages,
tokens, paths, user SQL file names, connections, credentials, and database
object identifiers.

- [ ] **Step 5: Add a dedicated performance workflow**

`performance.yml` runs on `ubuntu-24.04` only by `workflow_dispatch`, nightly
schedule, and `workflow_call`, outside generic PR CI. The reusable call
requires `commit_sha`, checks out that immutable SHA, asserts
`git rev-parse HEAD == commit_sha`, and returns the exact artifact name
`performance-${commit_sha}` plus a successful-gate output. `release.yml`
invokes this local reusable workflow with the tag's `GITHUB_SHA` and declares
its assembly job dependent on that returned success; it never waits for an
unrelated scheduled run. Pin every third-party
action to a full commit SHA. Use separately measured cold-session and
high-volume warm-operation populations, fixed fixtures, and publish every raw
observation as JSON plus
`docs/evidence/task-9-performance.md` in that exact named artifact.

Add an inactive root `performance` profile whose only additional modules, in
order, are the Task 4 native test target and
`tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.performance.tests`.
The performance module is an `eclipse-test-plugin` selecting that target and
inherits the absolute `dbeaver.product.path` enforcer, JUnit 5 provider,
`failIfNoTests`, UI harness/thread, and captured DBeaver product/application
settings. Default verification discovers no performance-budget test. The
dedicated workflow prepares the allowlisted Linux 26.1.0 product, starts a
real display, runs the workspace bootstrap, and executes:

```bash
./mvnw -B -Pperformance \
  -Ddbeaver.product.path="${DBEAVER_PRODUCT_PATH}" \
  -Dperformance.samples=2 \
  -Dperformance.coldSessions=20 \
  -Dperformance.warmupRuns=1 \
  -Dperformance.measuredRuns=3 \
  -Dperformance.operationsPerRun=200 verify
npm --prefix web exec -- playwright install --with-deps chromium
PERFORMANCE_SAMPLES=2 \
PERFORMANCE_COLD_SESSIONS=20 \
PERFORMANCE_WARMUP_RUNS=1 \
PERFORMANCE_MEASURED_RUNS=3 \
PERFORMANCE_OPERATIONS_PER_RUN=200 \
PERFORMANCE_SCROLL_FRAMES_PER_RUN=300 \
  npm --prefix web exec -- playwright test tests/largeDocument.spec.ts
```

Enforce these release budgets:

| Operation | 1 MiB | 10 MiB |
|---|---:|---:|
| cold snapshot to read-only render, p95 | 3 s | 10 s |
| edit acknowledgement, p95 / p99 | 50 / 100 ms | 120 / 250 ms |
| selection acknowledgement, p95 / p99 | 30 / 75 ms | 50 / 120 ms |
| canonical patch, p95 / p99 | 60 / 120 ms | 150 / 300 ms |
| scroll frame, p95 | 33 ms | 50 ms |

For each fixture and each of two independent samples, launch 20 distinct
editor/Browser sessions and record snapshot-to-read-only-render for every
session; there is no unmeasured cold start. Twenty observations are the
minimum population used for the empirical nearest-rank p95. Dispose and verify
each session before creating the next.

Warm metrics use a separate session per sample. Perform one explicitly
unmeasured warm-up run, then three measured runs. Each measured run contains
200 edit acknowledgements, 200 selection acknowledgements, 200 canonical
patch round trips, and 300 scroll frames. Calculate median/p95/p99 from raw
events across the three measured runs; three run summaries are not themselves
the percentile population. Store fixture, sample, run, operation index,
monotonic start/end timestamps, and environment metadata for each observation.

A breach in sample one is a warning artifact; fail the gate only when the same
fixture/metric breaches in both independent samples. Missing observations,
population-size mismatch, timer anomalies, test errors, and leak/disposal
failures are immediate hard failures and are never retried as performance
noise.

- [ ] **Step 6: Run hardening verification**

```bash
./mvnw -B verify
npm --prefix web test
```

Expected: recovery provenance is explicit, native editor remains usable, no
session/listener/worker survives lifecycle tests, sensitive sentinels are
absent, and the dedicated performance evidence is attached.

- [ ] **Step 7: Commit and stop**

```bash
git add pom.xml bundles tests web .github/workflows/performance.yml \
  docs/evidence
git commit -m "feat: add safe recovery and compatibility diagnostics"
```

Open the Task 9 draft PR.

### Task 10: Signed p2 packaging and compatibility CI

**Files:**

- Modify: `features/io.github.bakhtiiartashbolotov.dbeaver.monaco.feature/feature.xml`
- Create: `features/io.github.bakhtiiartashbolotov.dbeaver.monaco.source.feature/pom.xml`
- Create: `features/io.github.bakhtiiartashbolotov.dbeaver.monaco.source.feature/feature.xml`
- Create: `features/io.github.bakhtiiartashbolotov.dbeaver.monaco.source.feature/build.properties`
- Modify: `repository/category.xml`
- Create: `.github/workflows/compatibility.yml`
- Create: `.github/workflows/canary.yml`
- Create: `.github/workflows/release.yml`
- Create: `.github/dependabot.yml`
- Create: `docs/compatibility.md`
- Create: `scripts/install-smoke.sh`
- Create: `scripts/install-smoke.ps1`
- Create: `scripts/run-installed-product-e2e.sh`
- Create: `scripts/run-installed-product-e2e.ps1`
- Create: `scripts/verify-compatibility-evidence.sh`
- Create: `scripts/package-release.sh`
- Create: `scripts/verify-release.sh`
- Create: `scripts/verify-npm-licenses.mjs`
- Create: `releng/signing/allowed-cert-sha256.txt`
- Create: `releng/installed-e2e/pom.xml`
- Create: `releng/baseline/dbeaver-ce-26.1.3-linux-x86_64.tar.gz.sha256`
- Create: `releng/baseline/dbeaver-ce-26.1.3-macos-x86_64.dmg.sha256`
- Create: `releng/baseline/dbeaver-ce-26.1.3-macos-aarch64.dmg.sha256`
- Create: `releng/baseline/dbeaver-ce-26.1.3-windows-x86_64.zip.sha256`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.e2e.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/e2e/CompatibilityOutcome.java`
- Create: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.e2e.tests/src/io/github/bakhtiiartashbolotov/dbeaver/monaco/e2e/CompatibilityMatrixE2ETest.java`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.e2e.tests/pom.xml`
- Modify: `tests/io.github.bakhtiiartashbolotov.dbeaver.monaco.e2e.tests/META-INF/MANIFEST.MF`
- Modify: `scripts/prepare-dbeaver-product.sh`
- Modify: `scripts/prepare-dbeaver-product.ps1`
- Modify: `pom.xml`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core/pom.xml`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/pom.xml`
- Modify: `bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/pom.xml`
- Modify: `web/pom.xml`
- Modify: `features/io.github.bakhtiiartashbolotov.dbeaver.monaco.feature/pom.xml`
- Modify: `repository/pom.xml`

**Interfaces:**

- Consumes: complete vertical slice and all standard verification commands.
- Produces: installable p2 repository, compatibility matrix evidence, SBOM,
  signed binary/source artifacts, license inventory, checksums, and
  release-channel metadata.

- [ ] **Step 1: Write the failing release-artifact check**

`scripts/verify-release.sh` has two required explicit modes. `--structure`
must require:

```text
repository/target/repository/content.jar
repository/target/repository/artifacts.jar
feature group io.github.bakhtiiartashbolotov.dbeaver.monaco.feature.feature.group
source feature group io.github.bakhtiiartashbolotov.dbeaver.monaco.source.feature.feature.group
Apache-2.0 LICENSE
Maven CycloneDX SBOM
npm CycloneDX SBOM
third-party license inventory
source artifact for every shipped bundle
```

`--structure` applies those checks to the development reactor paths above.
`--signed` is intentionally self-contained for a clean assembly job: it
requires this exact `dist/` set and no other regular file:

```text
dbeaver-monaco-editor-p2-<version>.zip
dbeaver-monaco-editor-source-<version>.zip
dbeaver-monaco-editor-maven-sbom-<version>.cdx.json
dbeaver-monaco-editor-web-sbom-<version>.cdx.json
THIRD-PARTY-LICENSES-<version>.txt
compatibility-evidence-<commit-sha>.zip
SHA256SUMS
```

Transport-only effective-version/commit files, individual `.sha256` sidecars,
and workflow manifests are forbidden in `dist/`. `--signed` extracts the two
release ZIPs and compatibility ZIP into private temporary directories and
runs the structural/evidence predicates against their contents and p2
metadata. It must not depend on
`repository/target/repository` or any other Maven workspace output.
`--signed` also requires a concrete non-`SNAPSHOT` effective version, a
strictly verified JAR signature for every shipped plugin/feature, the
allowlisted signer fingerprint, the complete compatibility evidence, and
`dist/SHA256SUMS`. That sorted manifest covers exactly the six named payload
files above and excludes only itself. Optional provenance is created and
published afterward outside `dist/`; it is deliberately not a manifest
payload. An unlisted, missing, duplicate, or transport-only file fails.
Calling the script without exactly one supported mode is an error.

Both modes reject external asset URLs in packaged web resources and unresolved
version-property tokens in p2/JAR metadata. Development `--structure` checks
may use the repository's normal `SNAPSHOT` version; `--signed` may not. The
script must inspect p2 metadata and every plugin/feature JAR, not infer
completeness from Maven modules. It must also reject every test module,
JUnit/jqwik/H2 package, and fixture symbolic name from runtime/source features
and p2 metadata.

- [ ] **Step 2: Run the release check and observe failure**

```bash
bash scripts/verify-release.sh --structure
```

Expected: non-zero exit because release artifacts are not complete.

- [ ] **Step 3: Complete p2 metadata, sources, and install smoke test**

Include exactly the core, bridge, web, and UI bundles in the runtime feature.
Generate source bundles with Tycho 5.0.3 for core, bridge, UI, and web/protocol
sources; include them in a separate source feature. Put both feature groups in
a named category. The release source archive must also contain the exact
tracked sources, build scripts, schema, lockfiles, `LICENSE`, and notices for
the tagged commit. Configure exact reactor artifact names:

```text
repository/target/dbeaver-monaco-editor-p2-<version>.zip
repository/target/dbeaver-monaco-editor-source-<version>.zip
```

The build fails when either expected ZIP is missing or when another candidate
p2/source ZIP makes selection ambiguous.

`run-installed-product-e2e.sh` and `run-installed-product-e2e.ps1` are the
only public compatibility wrappers and have the same exact contract:
`(dbeaverVersion, os, architecture, p2Zip, pluginVersionFile,
p2Sha256File, evidenceDirectory)`. `pluginVersionFile` must be the exact
single-line `effective-plugin-version.txt`; `p2Sha256File` must be the exact
`${p2ZipBasename}.sha256` sidecar. They reject a URL, glob, missing/non-ZIP
file, ambiguous candidate, non-empty evidence directory, malformed sidecar,
or p2 filename/version unequal to the plugin version file. The wrapper uses
`dbeaverVersion` only as a committed product-allowlist key and never confuses
it with the plugin version. It resolves the product URL and digest only from
that allowlist, verifies both product and p2 SHA-256, creates one private
temporary root, and owns cleanup in `trap`/`finally`.

Within that one lifetime, the wrapper clones the checksum-verified product,
extracts the exact p2 ZIP, and delegates installation/discovery/reinstall
operations to the OS-specific `install-smoke` helper. The helper accepts only
the wrapper-owned clone and extracted local p2 path, rejects a path outside
the wrapper temp root, invokes that clone's p2 director, installs the runtime
feature, confirms the alternative presentation, then uninstalls/reinstalls to
detect stale state. It never creates a second product clone or cleans the
owner's clone.

The same wrapper then runs:

```bash
./mvnw -B -f releng/installed-e2e/pom.xml \
  -Ddbeaver.product.path="${WRAPPER_OWNED_INSTALLED_PRODUCT}" \
  -Dmonaco.p2.sha256="${VERIFIED_P2_SHA256}" \
  -Dcompatibility.output="${EVIDENCE_DIRECTORY}/outcomes.json" verify
```

`releng/installed-e2e/pom.xml` is a dedicated aggregator whose only modules
are the Task 4 installed-product target, H2 test fixture, and E2E test plugin.
It fails if any core/bridge/web/UI production bundle, feature, or repository
project enters its reactor. The test target resolves the production plugin
only from the already installed product clone; the reactor contributes only
test harness code. Before assertions, the E2E test matches installed runtime
bundle IDs/digests against the exact p2 manifest and recorded p2 SHA-256.
Thus install smoke and all ten outcomes execute against the same clone and the
same p2 bytes. The wrapper writes evidence atomically and cleans the clone only
after the test process exits.

- [ ] **Step 4: Add stable compatibility jobs**

`compatibility.yml` has exactly `pull_request`, `push` to `main`, and
`workflow_dispatch` triggers, with no path filter that could leave a required
check pending. Set workflow-level `permissions: { contents: read }`; no job
widens them, receives secrets, persists checkout credentials, or uses
`pull_request_target`. Branch protection requires the stable
`aggregate-compatibility` job on pull requests and `main`. The scheduled
dynamic target belongs only to the separate warning canary in Step 5.

Run the following required architecture rows for both pinned versions, with
full-commit-SHA action pins:

```text
Ubuntu x86_64 on ubuntu-24.04
Windows x86_64 on windows-2025
macOS x86_64 on macos-15-intel
macOS aarch64 on macos-15
```

```text
DBeaver 26.1.0 — required
DBeaver 26.1.3 — required
```

Compile the release reactor against 26.1.0. Each job asserts the actual runner
architecture before selecting its allowlisted archive. Install and execute smoke tests
against both checksum-pinned targets. The 26.1.3 product digests are committed
under `releng/baseline/`; jobs never resolve an unpinned download. Native
runner evidence is required for SWT Browser checks.

The compatibility workflow begins with one `build-p2` job on
`ubuntu-24.04`. It checks out the exact commit, bootstraps, runs
`./mvnw -B clean verify` against 26.1.0, records the effective
`PROJECT_VERSION`, and requires exactly one
`repository/target/dbeaver-monaco-editor-p2-${PROJECT_VERSION}.zip`. It writes
the exact `${p2ZipBasename}.sha256` sidecar and
`effective-plugin-version.txt` beside it, then uploads precisely those three
files as the immutable workflow artifact
`compatibility-p2-${GITHUB_SHA}`. Zero/multiple ZIPs or an unexpected file
fails before upload.

Every OS/version/architecture matrix job downloads that exact named artifact,
verifies its SHA-256 and effective version, and invokes the OS-specific
`run-installed-product-e2e` wrapper. It does not rebuild the p2 ZIP and does
not invoke the reactor-injected `-Pnative-e2e` command directly.

`CompatibilityOutcome` is a closed enum with the ten names below.
`CompatibilityMatrixE2ETest` owns one assertion method per outcome and writes a
machine-readable result that fails if any enum member is absent, duplicated,
or unsuccessful. It is launched only by the installed-product aggregator
inside the wrapper above.

On every OS/version/architecture row, exercise these ten product outcomes:

1. install and discover the alternative SQL presentation;
2. switch Native→Monaco→Native without replacing `IDocument`;
3. preserve canonical text, dirty state, primary selection, and focus;
4. use `Ctrl+D`/`Cmd+D` to add the next occurrence;
5. type and paste through multiple cursors and undo once through Eclipse;
6. wheel-scroll, minimap, find, and keyboard navigation without page scroll;
7. save current canonical text through DBeaver;
8. execute selected statement with `Ctrl+Enter` into the native result grid;
9. execute a script through DBeaver's native results lifecycle;
10. inject a critical Browser failure and recover to usable Native presentation.

The tests must drive real product surfaces for presentation commands,
save/execute, result grids, and Browser failure. Reusing standalone web mocks
does not satisfy a compatibility outcome. Each row writes exactly
`artifacts/compatibility/<dbeaver-version>/<os>-<arch>/outcomes.json` plus
product/p2 digests and runtime bundle identities, then uploads a uniquely
named row artifact containing only that directory.

An `aggregate-compatibility` job downloads all row artifacts into a clean
tree and runs `scripts/verify-compatibility-evidence.sh`. The script requires
exactly eight unique rows (two DBeaver versions × four architecture rows),
exactly one successful instance of every `CompatibilityOutcome` per row,
identical p2 SHA-256 across all rows, and no extra/missing/duplicate result.
It creates exactly
`artifacts/compatibility/compatibility-evidence-${GITHUB_SHA}.zip` and a
SHA-256 sidecar. The workflow uploads both as
`compatibility-evidence-${GITHUB_SHA}`; missing matrix jobs cannot produce a
partial green aggregate.

- [ ] **Step 5: Add the warning canary**

Run weekly against the newest available stable/EA target without changing the
release compile property. Resolve it only from the official DBeaver archive,
record the exact version/URL/official SHA-256 at the start of the run, and use
that immutable tuple for the rest of the job. The dynamic canary artifact is
never promoted into a release. Canary failure opens or updates a compatibility
issue and does not suppress stable required checks.

Keep canary writes in separate `canary.yml`, triggered only by schedule or
owner `workflow_dispatch` from trusted `main`; it has no pull-request trigger.
All probe jobs use `permissions: { contents: read }`. Only a downstream
issue-upsert job, conditional on a completed canary failure and trusted
repository/ref checks, receives job-scoped
`permissions: { contents: read, issues: write }`. Neither
`compatibility.yml` nor any PR-reachable job receives `issues: write`.

- [ ] **Step 6: Add exact supply-chain and source gates**

Configure Dependabot for Maven, npm, and GitHub Actions. Generate Maven SBOM
with `org.cyclonedx:cyclonedx-maven-plugin:2.9.2`; generate the web SBOM with
`npm sbom --omit=dev --sbom-format cyclonedx`; generate/check the Maven
license inventory with `org.codehaus.mojo:license-maven-plugin:2.7.1`; and have
`verify-npm-licenses.mjs` walk every production entry in `package-lock.json`.
The bridge's shaded closure, Monaco notices, and exact `ajv@8.20.0` MIT
component/notice must appear in the inventory. Match the checked esbuild
metafile input graph to that Ajv production component and prove that no Ajv
compiler module entered the browser artifact. The Ajv package is a production
lock/SBOM component because its helper code is embedded even though its
compiler is not shipped. `json-schema-to-typescript`, esbuild, Acorn,
eslint-scope, and other development/build npm packages plus test-only JUnit,
jqwik, and H2 are reported in a separate non-runtime inventory and are not
shipped. The release web SBOM represents the production lockfile closure.
Run:

```bash
npm --prefix web audit --omit=dev
./mvnw -B verify
bash scripts/verify-release.sh --structure
```

Expected: no unresolved high/critical production vulnerability, all licenses
are compatible or explicitly approved, and the unsigned p2/source/SBOM/license
structure is complete. Signature and final-checksum success is not claimed
until Step 7.

- [ ] **Step 7: Sign before p2 metadata and verify every release JAR**

Add an inactive `release-sign` profile using
`org.apache.maven.plugins:maven-jarsigner-plugin:3.1.0`. The protected GitHub
`release` environment supplies `SIGNING_KEYSTORE_B64`, `SIGNING_STOREPASS`,
`SIGNING_KEYPASS`, and `SIGNING_ALIAS`; the workflow writes the keystore to an
ephemeral runner path and deletes it after use. Absence of any secret blocks
the release rather than producing unsigned artifacts.

Sign binary and source plugin/feature JARs in their package phase before the
repository module generates p2 metadata. Use SHA-256 digest/signature
algorithms and an approved timestamp authority. After repository assembly,
run `jarsigner -verify -strict -certs` on every
`plugins/*.jar` and `features/*.jar`, including source bundle/feature JARs,
and match each signer certificate fingerprint against
`releng/signing/allowed-cert-sha256.txt`; that file contains only reviewed
lowercase SHA-256 certificate fingerprints and no placeholder. A GitHub
artifact attestation may be added after this verification, but never
substitutes for JAR signing.

Repository metadata containers `content.jar` and `artifacts.jar` are not
module JARs and are not passed to `jarsigner`; their exact integrity is covered
by structural p2 inspection, the immutable p2 ZIP digest tested by the matrix,
and the final release SHA-256 manifest. Do not post-sign or rewrite them after
repository assembly.

After signing and repository assembly, the signing job creates two disjoint
transport directories:

```text
release-inputs/signed/payload/
  dbeaver-monaco-editor-p2-<version>.zip
  dbeaver-monaco-editor-source-<version>.zip
  dbeaver-monaco-editor-maven-sbom-<version>.cdx.json
  dbeaver-monaco-editor-web-sbom-<version>.cdx.json
  THIRD-PARTY-LICENSES-<version>.txt

release-inputs/signed/verification/
  effective-plugin-version.txt
  commit-sha.txt
  <one basename-matching .sha256 sidecar for each payload file>
```

`payload/` contains only the five eventual publishable signed-build payloads.
`verification/` is transport metadata only. The signing job rejects missing,
duplicate, cross-directory, or unexpected inputs and uploads the parent once
as immutable workflow artifact `signed-release-inputs-${GITHUB_SHA}`. No later
job rebuilds or rewrites either set.

After the signed p2 has passed the installed-product compatibility matrix,
`scripts/package-release.sh <version> <signedInputDirectory>
<compatibilityEvidenceZip>` first verifies all five sidecars and both
transport metadata files without copying them. It verifies the compatibility
ZIP's sibling transport sidecar, complete eight-row content, commit SHA, and
that every row's p2 digest equals the signed p2 digest. It then copies only the
five files from `payload/` plus the compatibility ZIP into a new empty
`dist/`, using the exact filenames declared in Step 1. It never copies
`verification/` or either evidence/payload sidecar.

The script writes sorted `dist/SHA256SUMS` over exactly those six regular
payloads. The manifest is never regenerated after publication; optional
provenance is produced afterward outside `dist/` and is deliberately outside
its coverage. The script rejects `SNAPSHOT` or malformed versions and proves
its argument equals the effective Maven version used to name every versioned
input artifact.

Order runtime/source bundle and feature modules before `repository` in the
reactor so repository metadata consumes already signed jars. A protected
signing build may be rehearsed only in an owner-approved manual
protected-environment job pinned to the already reviewed Task 10 commit SHA;
ordinary pull-request jobs never receive these secrets:

```bash
PROJECT_VERSION=0.1.0
./mvnw -B -Drevision="${PROJECT_VERSION}" -Prelease-sign clean verify
bash scripts/verify-release.sh --structure
```

Expected: every structural, JAR-signature, and signer-fingerprint gate passes
and the exact signed inputs are ready for matrix transport. Final
`package-release`/`--signed` success is intentionally not claimed until the
same signed p2 bytes pass Step 8's compatibility aggregation. Missing
credentials or an unsigned jar fails closed.

- [ ] **Step 8: Define the protected release workflow**

For a `v<version>` tag, `release.yml` derives `PROJECT_VERSION` from the tag
and rejects any mismatch with the effective Maven version, dirty state,
commit SHA, or `SNAPSHOT`. The protected `sign-build` job on `ubuntu-24.04`
executes exactly
`./mvnw -B -Drevision="${PROJECT_VERSION}" -Prelease-sign clean verify`,
verifies signatures/fingerprints, and uploads
`signed-release-inputs-${GITHUB_SHA}` as defined in Step 7.

A required eight-row `release-compatibility` matrix downloads that exact
artifact, verifies its sidecars, and passes the contained signed
`dbeaver-monaco-editor-p2-${PROJECT_VERSION}.zip` to the same
`run-installed-product-e2e` wrappers used by stable CI. Each wrapper installs
and runs all ten outcomes against one clone. The aggregate job produces
`compatibility-evidence-${GITHUB_SHA}` and verifies that every row names the
signed p2 digest. In parallel, a required job calls
`./.github/workflows/performance.yml` with `commit_sha: ${{ github.sha }}` and
requires its `performance-${GITHUB_SHA}` success output. Assembly names both
jobs in `needs`; a scheduled/manual result from another commit cannot satisfy
the release.

Only after both gates pass, an `assemble` job downloads the exact named signed
inputs to `release-inputs/signed/` and the exact named compatibility artifact
to `release-inputs/compatibility/`, which must contain exactly
`compatibility-evidence-${GITHUB_SHA}.zip` and its basename-matching
`.sha256` transport sidecar. It verifies the signed `payload/` sidecars from
`verification/` and the compatibility sidecar, then calls:

```bash
bash scripts/package-release.sh \
  "${PROJECT_VERSION}" \
  release-inputs/signed \
  "release-inputs/compatibility/compatibility-evidence-${GITHUB_SHA}.zip"
bash scripts/verify-release.sh --signed
```

Zero/multiple artifacts, a run/commit mismatch, or any p2 digest mismatch
fails. `assemble` never invokes Maven or signing, so the tested p2 is
byte-for-byte the published p2. Publish exactly the seven files allowed in
Step 1 (`SHA256SUMS` plus its six covered payloads). Do not publish
`verification/`, individual sidecars, effective-version/commit transport
files, or the compatibility sidecar. Optional GitHub provenance is created
and published afterward as a separate platform attestation, not copied into
`dist/`.

The workflow has no pull-request trigger, pins every third-party action to a
full commit SHA, uses `persist-credentials: false`, and defaults to
`contents: read`. Only the final publish job receives `contents: write`;
`id-token: write` and `attestations: write` are granted only when optional
provenance is enabled. No release job runs with secrets on an untrusted pull
request.

- [ ] **Step 9: Document the verified support matrix**

`docs/compatibility.md` must name each tested DBeaver/OS/architecture/Browser
combination and its exact workflow run. Do not claim support based only on
compilation.

- [ ] **Step 10: Commit the release system and stop**

```bash
git add features repository releng .github docs scripts pom.xml bundles tests web
git commit -m "build: package and verify cross-platform p2 release"
```

Open the Task 10 draft PR. The vertical slice is ready for product-owner
acceptance only after all required jobs and manual UX evidence pass.

## Plan completion rule

After each task:

1. Open or update exactly one draft pull request.
2. Run an independent review against the design and relevant ADRs.
3. Resolve blocking findings in the same task branch.
4. Merge only after the acceptance gate passes.
5. Start the next task in a fresh cloud session and branch.

Do not execute several tasks in one cloud run merely because the previous task
appears straightforward.
