# Cloud development bootstrap

This guide takes the approved documentation pack into a new GitHub repository
and starts the first bounded cloud-agent task.

## 1. Create the repository

Recommended repository:

```text
owner: bakhtiiartashbolotov
name: dbeaver-monaco-editor
visibility: public, unless early private development is preferred
default branch: main
license: do not add through GitHub; this pack already contains Apache-2.0
```

Create an empty repository without a generated README, `.gitignore`, or
license, so the starter pack can become the initial commit without conflicts.

If the final owner or repository name differs, change the Java/Maven namespace
before Task 1. Do not rename it piecemeal after production code exists.

## 2. Put this starter pack into Git

From the directory containing the files:

```bash
git init -b main
git add .editorconfig .gitattributes AGENTS.md LICENSE README.md \
  .github/pull_request_template.md docs
git status --short
git diff --cached --check
git commit -m "docs: add architecture and cloud development plan"
git remote add origin git@github.com:bakhtiiartashbolotov/dbeaver-monaco-editor.git
git push -u origin main
```

HTTPS is equally valid if SSH is not configured:

```bash
git remote add origin https://github.com/bakhtiiartashbolotov/dbeaver-monaco-editor.git
```

Check on GitHub that these paths render correctly:

```text
AGENTS.md
docs/superpowers/specs/2026-07-31-dbeaver-monaco-editor-design.md
docs/superpowers/plans/2026-07-31-bootstrap-and-vertical-spike.md
docs/agent-workflow.md
```

## 3. Configure repository safety

Enable these settings where the GitHub plan and repository visibility support
them:

- require a pull request before merging to `main`;
- block force pushes and branch deletion on `main`;
- require conversation resolution;
- prefer squash merge and automatically delete merged branches;
- enable secret scanning and push protection;
- enable dependency graph, Dependabot alerts, and security updates;
- enable private vulnerability reporting for a public repository;
- require status checks after Task 1 creates stable workflows.

For a solo repository, do not require an approval that the sole author cannot
satisfy. The review gate can initially be an orchestrator review plus passing
checks.

No application secrets are expected. The plugin must not need database
credentials, signing keys, GitHub tokens, or external service credentials to
build and test. Task 10 release signing uses a protected GitHub environment;
never expose those secrets to pull-request jobs or an implementation prompt.

## 4. Create the first milestone and issue

Create milestone:

```text
MVP Vertical Slice
```

Create issue:

```markdown
Title: Task 1 — reproducible Tycho and npm scaffold

Source:
docs/superpowers/plans/2026-07-31-bootstrap-and-vertical-spike.md

Scope:
Execute Task 1 only. Prove that the independent repository downloads the
official DBeaver CE 26.1.0 product archive, verifies its checked-in SHA-256,
uses that exact installation as the Tycho target, creates the planned empty
modules, and runs the smoke CI build.

Acceptance:
- Maven 3.9.16 wrapper and Node 24.18.1/npm 11.16.0 build are reproducible.
- The DBeaver archive checksum is pinned and the target contains only bundles
  shipped in that product.
- Production uses the DBeaver-only target; test modules use the separate,
  exact JUnit Platform test overlay, and test bundles are absent from p2.
- The pinned product's application/product IDs and public SQL editor API
  contract are captured unambiguously for later native harnesses.
- Public save/undo/redo/statement/script IDs and all toolbar/menu/global
  surfaces are mapped; any native format surface is recorded as safely
  guardable, explicitly absent, or a fail-closed blocker.
- `./mvnw -B verify` resolves the pinned target and passes.
- `npm --prefix web ci` and the initial web checks pass.
- No Monaco UI or DBeaver integration behavior is implemented.
- A draft pull request records exact commands and outputs.
- CI uses least-privilege permissions, explicit runner labels, and full-SHA
  action pins.

Stop conditions:
Follow AGENTS.md. Do not use a nonexistent versioned p2 URL, add an independent
Eclipse repository, or switch the DBeaver target to `latest`. Report a
reproducible blocker instead.
```

Do not create all implementation branches at once. Additional issues can be
created from the plan when the preceding task is accepted and its actual
interfaces are known.

## 5. Connect the cloud development environment

Connect the new GitHub repository to the remote coding environment. UI labels
vary, but the intended permissions are:

- Metadata: read;
- Contents: read/write, limited to this repository;
- Pull requests: read/write;
- Issues: read;
- Workflows: read/write, because numbered tasks create or update files under
  `.github/workflows/`;
- Actions and Checks: read;
- no organization administration or unrelated repository access.

GitHub documents `Workflows` as a separate repository permission when an app
must edit `.github/workflows/`; do not compensate by granting broader
administrative access:
[Choosing permissions for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app).

Select the repository's `main` branch as the base and start a fresh cloud task
for Issue Task 1.

For Task 1, allow outbound HTTPS only to `dbeaver.io`,
`downloads.dbeaver.net`,
`repo.maven.apache.org`, `nodejs.org`,
`registry.npmjs.org`, `github.com`, the GitHub endpoints required by
checkout/actions, and `release-assets.githubusercontent.com` for the official
DBeaver archive redirect. If the cloud policy blocks one, stop and allowlist
it; do not mirror artifacts to an unreviewed host or weaken checksum
verification.

Review network scope again before each later task. Task 3 adds
`cdn.playwright.dev`, `playwright.download.prss.microsoft.com`, and the signed
OS package mirrors used by the pinned runner for Playwright's `--with-deps`.
Task 10 additionally requires the one owner-approved timestamp-authority host
configured for release signing. Record each task-specific addition in its PR;
do not give every implementation session permanent unrestricted egress.

Before assigning Task 1, confirm the cloud image is Linux x86_64 and run this
read-only preflight:

```bash
uname -srm
bash --version
git --version
command -v curl || command -v wget
tar --version
unzip -v
command -v sha256sum || command -v shasum
command -v sha512sum || command -v shasum
java -version
node --version
npm --version
mvn --version
```

Task 1 requires Bash/Git, `curl` or `wget`, `tar`, `unzip`, SHA-256 and
SHA-512 tooling, Java 21, Node 24.18.1, npm 11.16.0, and an installed Maven
3.9.16 to generate and verify the wrapper. `unzip` is mandatory on the POSIX
cloud image because the checksum-locked lite wrapper uses the Maven binary
ZIP. A mismatch is an environment blocker. Change the cloud image or its
reviewed setup configuration; do not let the implementation agent install an
unpinned substitute during the task.

## 6. First cloud-agent prompt

Replace `[ISSUE_URL]`, then copy this prompt without adding the whole
conversation history:

```text
Work on [ISSUE_URL], “Task 1 — reproducible Tycho and npm scaffold”.

Before editing, read these files completely:
- AGENTS.md
- docs/superpowers/specs/2026-07-31-dbeaver-monaco-editor-design.md
- docs/architecture/README.md and all current ADRs
- Task 1 only in
  docs/superpowers/plans/2026-07-31-bootstrap-and-vertical-spike.md

Inspect the repository and git status. State the task scope, expected files,
the observed Linux/architecture and toolchain prerequisites, and any conflict
with the documents before changing anything. Do not edit until the Task 1
preflight matches `docs/cloud-development.md`.

Execute Task 1 only. Follow the plan's test-first/checkpoint sequence and its
exact pinned versions. Do not start Task 2, implement Monaco behavior, replace
the DBeaver target with “latest”, or make an unapproved architecture change.

Commit at the plan checkpoints, run every Task 1 verification command, and
open a draft pull request using the repository template. End with the mandatory
AGENTS.md final report, including exact observed PASS/FAIL evidence and the
repository URL, task branch, and draft PR URL. If the
checksum-pinned product target, Tycho resolution, or a public API differs,
stop with reproducible evidence and options; do not improvise around it.
```

As soon as the draft PR exists, send its URL and the repository URL to the
orchestrator. Do not wait for merge; review starts on the draft.

## 7. Review the first pull request

Do not merge merely because the scaffold compiles. Verify:

- the baseline script verifies the committed SHA-256 before extraction;
- the checksum was obtained from the exact official
  `downloads.dbeaver.net/community/26.1.0/checksum/...sha256` URL;
- the target points only at the extracted DBeaver 26.1.0 installation;
- the test target adds only exact JUnit Platform artifacts and is selected only
  by test modules;
- no independent Eclipse repository can inject newer platform bundles;
- exact application/product IDs are extracted unambiguously from the pinned
  product and recorded for later UI harnesses;
- runtime manifest ranges are bounded from the verified minimum rather than
  exact-matching a product string or qualifier;
- Tycho is 5.0.3 and Java release is 21;
- Maven is 3.9.16, the wrapper pins and enforces the verified binary-ZIP
  `distributionSha256Sum`, and POSIX bootstrap checks `unzip` before wrapper
  execution;
- Node 24.18.1/npm 11.16.0 are build-time only;
- module names match the design;
- core production source has no platform dependencies;
- generated output and build artifacts are ignored;
- CI commands are the same commands developers run;
- CI uses `ubuntu-24.04`, least-privilege read permissions, full-SHA action
  pins, no PR secrets, and non-persistent checkout credentials;
- no UI behavior or extra dependency was added;
- the PR contains actual command evidence, not only a check mark.

The orchestrator or another reviewer who did not implement the change performs
a read-only review for every PR. A separate fresh cloud reviewer is recommended
for Tasks 1–3 and required for the native/security/release gates in Tasks
4–10. Use the prompt in `docs/agent-workflow.md`.

## 8. After Task 1

Once Task 1 is merged:

1. Update local `main`.
2. Run `bash scripts/bootstrap-workspace.sh` in the fresh checkout.
3. Create the Task 2 issue from the accepted plan.
4. Start a new cloud task and branch.
5. Give the agent the plan path and Task 2, not the entire product request.
6. Review interfaces and generated protocol artifacts before merging.
7. Continue one task at a time.

After merge, return the merged PR URL and merge commit to the orchestrator so
the next issue/prompt is based on the exact accepted state.

## 9. Optional local prerequisites

Cloud development and CI should remain authoritative, but local reproduction
is useful:

| Platform | Required |
| --- | --- |
| All | Git, Java 21 JDK, Node 24.18.1, npm 11.16.0; installed Maven 3.9.16 only to generate/verify the wrapper in Task 1 |
| Windows | PowerShell or Git Bash; installed DBeaver CE for manual smoke test |
| macOS | Xcode command-line tools; installed DBeaver CE |
| Linux | `tar`, `unzip`, checksum tools; GTK-compatible desktop or Xvfb for SWT tests; installed DBeaver CE |

After Task 1 lands:

```bash
bash scripts/bootstrap-workspace.sh
./mvnw -B verify
npm --prefix web ci
npm --prefix web run lint
npm --prefix web test
npm --prefix web run build
```

Cross-platform SWT behavior must be proven by native GitHub Actions runners or
explicit manual evidence. A Linux-only cloud preview is not proof of Windows
or macOS compatibility.
