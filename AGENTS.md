# DBeaver Monaco Editor — Agent Instructions

These instructions apply to every file in this repository. A deeper
`AGENTS.md`, if introduced later, may add stricter instructions for its
subtree but may not weaken the invariants below.

## 1. Mission

Build an Apache-2.0 DBeaver Community extension that offers Monaco as an
alternative presentation inside the existing SQL Editor. Monaco supplies the
editing experience. DBeaver remains responsible for the canonical document,
SQL execution, connections, transactions, dirty state, and result grids.

The first supported DBeaver line starts at 26.1.0. The extension must run on
Windows, macOS, and Linux using the system SWT Browser.

## 2. Instruction precedence

When instructions differ, apply this order:

1. The current explicit user request.
2. This `AGENTS.md`.
3. The approved design in
   `docs/superpowers/specs/2026-07-31-dbeaver-monaco-editor-design.md`.
4. Accepted ADRs under `docs/architecture/decisions/`.
5. The current numbered task in
   `docs/superpowers/plans/2026-07-31-bootstrap-and-vertical-spike.md`.
6. Other documentation.

Do not resolve a genuine architectural conflict by guessing. Stop and report
the conflicting statements with a recommended resolution.

## 3. Required reading before edits

Before changing code or build files:

1. Read this file completely.
2. Read the approved design completely.
3. Read the ADR index and every ADR relevant to the task.
4. Read the complete current implementation-plan task, including its
   interfaces and verification commands.
5. Inspect the existing tree and `git status`.
6. State which plan task you are executing and which files you expect to
   change.
7. When `scripts/bootstrap-workspace.sh` exists, run it once in every fresh
   checkout/cloud session before the first Maven command. Do not assume the
   ignored checksum-pinned DBeaver target survived from a previous session.

Execute one numbered plan task per cloud run and pull request unless the user
explicitly expands the scope.

## 4. Non-negotiable architecture

### Integration

- Contribute through `org.jkiss.dbeaver.sqlPresentation`.
- Do not fork, patch, vendor, or modify DBeaver.
- Do not invoke `ExtraPresentationManager` directly.
- Do not import packages containing `.internal`.
- Use only exported/public DBeaver and Eclipse APIs.
- Keep all `org.jkiss.*`, `org.eclipse.*`, JFace, and SWT calls in the UI
  bundle behind `DBeaverEditorAdapter` or another explicitly approved port.
- Build against the checksum-pinned DBeaver 26.1.0 product baseline prepared
  by `scripts/prepare-dbeaver-target.sh`; never substitute `latest`.
- The target is the exact bundle set in that product archive. Do not add an
  independent Eclipse p2 repository or a historical DBeaver update URL.
- Compile against 26.1.0. Task 10 introduces the separately checksum-pinned
  26.1.3 product archives and compatibility matrix; Tasks 1–9 do not invent or
  run that infrastructure unless their own task explicitly says otherwise.
- Do not exact-match the DBeaver product version at runtime. Use bounded OSGi
  package/bundle ranges anchored to the verified minimum, then capability
  probes and a version-specific adapter. Compatible patch upgrades should
  continue to work; incompatible changes fail closed for Monaco only.

### Document model

- Eclipse `IDocument` is the canonical source of text.
- Monaco `ITextModel` is a projection.
- Eclipse's undo manager is authoritative.
- DBeaver owns SQL execution and native results.
- Offsets crossing the bridge are UTF-16 code-unit offsets.
- A Monaco multi-edit is one compound Eclipse change, applied from the largest
  offset to the smallest.
- Text changes are ordered and are never debounced, coalesced, or dropped.
- Origin guards must prevent Java↔Monaco echo.
- Save, execute, format, and presentation switching require a revision
  barrier that covers readiness epoch, text revision, document stamp,
  acknowledged edit sequence, and acknowledged selection sequence.
- Before any web- or native-origin host command, atomically freeze Monaco and
  complete the typed flush request/response. Invoke native code only when all
  dispatched edit/selection sequences are acknowledged and the returned
  barrier exactly matches current canonical state. Never wait for JavaScript
  on the SWT thread.
- Native DBeaver toolbar, menu, and global keybinding commands must enter the
  same barrier through the scoped Monaco command guard; web routing alone is
  insufficient.
- Native formatting is reused only through the typed `Format` route and the
  same guard/barrier; the plugin does not implement a second formatter. If no
  native format surface exists, formatting is an optional disabled feature.
  If a mutating format surface exists but cannot be guarded, Monaco must not
  become editable.
- Never silently replace `IDocument` with a Monaco snapshot.
- Every document-, selection-, and command-bearing message carries the
  current monotonic `readinessEpoch`. Document messages also carry the
  applicable revision and `documentStamp`; every edit batch carries both base
  values. Before a full resync overwrites the projection, freeze and commit a
  bounded correlated Browser recovery export. The session stores an explicit
  `CapturingRecovery -> PreparingSnapshot` resync transaction; only the exact
  committed handle bound to the current activation/resync/source/request tuple
  and matching snapshot-capture identity may increment the epoch/reset
  sequences and authorize one new snapshot. Prepared-before-store, wrong,
  duplicate, and late callbacks are no-ops and can never overwrite. Messages
  from an older epoch are ignored or rejected with the typed stale-epoch code.
- Initial snapshots and external canonical patches have distinct web-to-host
  acknowledgements. `document.ack` is reserved for the host-to-web
  acknowledgement of a Monaco edit.
- Edit, selection, flush, recovery-export, and command sequences are scoped to
  one epoch. Initial/resync snapshot plus acknowledgement explicitly reset
  edit and selection high-water marks to zero.
- Selection updates carry epoch, revision, stamp, and a monotonic sequence and
  become command-visible only after acknowledgement.
- Canonical patches use Monaco's non-undoing application path and must not
  enter the Monaco undo stack.
- Before an external canonical patch, freeze and drain the Browser queue. Send
  an incremental patch only when the flush barrier exactly matches the
  retained pre-change canonical state; otherwise preserve the Browser
  projection as recovery data and resync/fall back.
- Capture inverse substrings before a compound multi-edit. A partial expected
  document failure must restore and verify pre-batch text before fallback;
  never present a partially modified document as a successful Native recovery.
- All undo/redo surfaces—keybindings, context menu, command palette, and
  programmatic web-facade calls—route through Eclipse.
- Command requests use separate host-assigned `WEB` and `NATIVE` monotonic
  per-epoch sequence namespaces and a bounded replay ledger. Origin is not
  client-controlled. An exact retry returns the cached response; a native
  handler is invoked at most once for that request. The ledger's single-use
  completion permit caches the full `EditorCommandResponse`, including its
  applied barrier; caching only `CommandResult` is forbidden.
- One physical command-guard activation exists per Monaco activation. Resync
  moves that same guard to blocking mode, revokes the old logical lease, and
  later rebinds it atomically to a fresh current-epoch lease after reproof.
  Never remove it during resync or install a second activation. Loss of the
  exact stored lease is critical even while the session is still `SYNCING`.

### Failure behavior

- Distinguish the SQL-editor lifetime from a Monaco activation. The former
  owns the circuit breaker and unresolved recovery material until explicit
  resolution or editor close. Each activation owns a fresh Browser, asset
  lease/token, bridge/session, listeners, replay state, and physical guard.
  Only the loopback server service is process-scoped; leases are never reused.
- A missing critical capability makes the Monaco presentation unavailable.
- A missing optional capability disables only that feature.
- Unknown incompatible DBeaver versions fail closed for Monaco only.
- The native SQL Editor, document, connection, and result tabs must remain
  usable.
- Permit one automatic full resync from `IDocument`. Repeated mismatch enters
  recovery/fallback instead of retrying forever.
- The one-resync allowance is consumed for the SQL-editor lifetime
  and is never reset after a successful resync or Native→Monaco reactivation.
- Initial snapshot acknowledgement and recovery-checkpoint eligibility keep
  Monaco read-only in `SYNCING` until both carry the same current
  `(readinessEpoch, revision, documentStamp)`. Mutation/compound-undo proof is
  epoch-bound rather than document-revision-bound. Editing may enter `READY`,
  or optional-only `DEGRADED`, only after a separate epoch-bound live
  command-guard lease proves native save/undo/redo/statement/script routing.
  These three readiness facts are stored in the session context and none may
  be inferred from task order.
- After startup, a validated document acknowledgement or acknowledged
  canonical patch advances the current document-readiness stamp atomically;
  it does not invalidate the live mutation proof or command-guard lease for
  the same epoch. A new epoch clears all readiness facts. Delayed facts from
  an older epoch, including headroom-loss events with coincident revision and
  stamp values, never enable or disable the current session.
- The host recovery journal has explicit byte, entry-count, and recovery-text
  limits. It may compact acknowledged entries into a bounded checkpoint, but
  it never evicts an unacknowledged entry. Capacity is reserved before
  canonical mutation. If reservation fails, reject the batch with
  `RECOVERY_CAPACITY_EXCEEDED`, leave `IDocument` unchanged, freeze Monaco
  read-only, and offer explicit export/Native recovery choices.
- Protocol-size eligibility does not imply edit eligibility. Before enabling
  input, after an external canonical replacement, and after every
  acknowledgement/compaction, deterministic overflow-safe accounting must
  leave room for the current checkpoint, one maximum 8 MiB edit batch, and
  the bounded 64 KiB journal-entry metadata. Otherwise report
  `RECOVERY_CAPACITY_EXCEEDED`; per-batch reservation still remains mandatory.
- Every host-to-web `DocumentAck` reports typed `recoveryEligible`. Snapshot
  and canonical-patch acknowledgements are distinct web-to-host messages. A
  false edit acknowledgement revokes further Monaco input; eligibility is
  never inferred from a successful canonical apply alone.
- Recovery can reproduce only state received by the Java host or explicitly
  exported from a still-live Browser. Never claim recovery of undelivered
  keystrokes, and never auto-apply recovery text to `IDocument`. Activation
  disposal transfers unresolved bounded material to the SQL-editor owner;
  erase it only after explicit resolution/discard or editor close.
- The external canonical-change queue is bounded by both entry count and a
  64 MiB aggregate conservative retained UTF-16/metadata budget. Reserve with
  checked arithmetic before copying exact changed segments. A count or byte
  overflow starts recovery capture without dropping/coalescing text and
  without claiming resync is already authorized.

### Runtime and security

- Use the system SWT Browser; never bundle Chromium or Electron.
- Node.js is a build dependency only.
- Serve bundled assets from `127.0.0.1` on a random port.
- Bind the literal IPv4 bytes `{127, 0, 0, 1}` without hostname resolution.
- Require an unguessable per-session token owned by the server lease and the
  exact shared policy in `web/security/content-security-policy.txt`. Callers
  never supply a token or policy.
- Do not load runtime assets from a CDN or make external web requests.
- Reject external navigation, unexpected origins, unknown commands, stale
  sessions, oversized messages, and schema-invalid payloads.
- Bound JSON parser nesting, decoded string length, and number length before
  mapping; schema validation is not a substitute for parser resource limits.
- Every wire integer visible to TypeScript must stay within
  `Number.MAX_SAFE_INTEGER`; text offsets and lengths must also stay within
  `Integer.MAX_VALUE`. Use shared schema definitions and cross-language
  max/overflow fixtures. A Java `long` is not permission to send an
  unrepresentable JavaScript number.
- Select JSON Schema draft 2020-12 explicitly in both validators
  (`Ajv2020` and NetworkNT `SpecificationVersion.DRAFT_2020_12`); never rely
  on a library default dialect.
- Ajv compiles the schema only during the build. Its temporary standalone
  CommonJS output is bundled with exact direct `esbuild@0.28.1` into
  self-contained browser ESM, including every pinned runtime helper. Browser
  output must have no external import, Ajv compiler module, unresolved/global
  direct `require`/`eval` call, or unresolved global `Function` call/constructor,
  and CSP must never add `unsafe-eval`.
  Verify executable calls with AST plus lexical-scope analysis; raw substring
  scans misclassify bound esbuild helpers and metadata strings. Node's
  no-string-codegen test and a real-browser exact-CSP test are both required.
- JavaScript may invoke only a typed command allowlist.
- Logs and diagnostics must not contain SQL text, credentials, connection
  URLs, database object names, or arbitrary bridge payloads.
- GitHub-hosted runner labels are explicit; do not use `*-latest`.
- Every third-party GitHub Action is pinned to a full commit SHA with its
  release tag in a comment. Dependabot may propose reviewed SHA updates.
- Pull-request workflows use least privilege, never
  `pull_request_target`, never receive release secrets, and do not persist
  checkout credentials.
- Stable compatibility runs on `pull_request`, pushes to `main`, and manual
  dispatch with workflow-level `contents: read`; its aggregate is the required
  status. Dynamic scheduled targets stay in the warning-only canary.

### Licensing

- Project license: Apache License 2.0.
- Do not copy GPL Equo source, generated output, or assets.
- Every new runtime dependency requires its exact version, license, reason,
  security assessment, and OSGi packaging impact in the pull request.
- If generated browser code embeds part of an npm package, keep that exact
  package in production dependencies and the release SBOM/license inventory
  even when its compiler or generator runs only at build time.
- Transport verification files and per-file sidecars never enter release
  `dist/`. Task 10's exact six-payload allowlist plus `SHA256SUMS` is
  authoritative; optional provenance is created outside `dist/` afterward.
- Strong-copyleft runtime dependencies require explicit owner approval.

## 5. Planned module boundaries

```text
bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.core
    Pure Java 21 state machines, synchronization rules, ports, capability
    model, and protocol-facing value types.

bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge
    Explicit private wire envelope, strict closed-union JSON Schema validation,
    exhaustive envelope/domain mapping, message bounds, and privately packaged
    JSON dependencies.

bundles/io.github.bakhtiiartashbolotov.dbeaver.monaco.ui
    DBeaver presentation, DBeaver adapter, SWT Browser host, loopback asset
    server, selection provider, command router, lifecycle/disposal.

protocol
    JSON Schema source of truth and language-neutral contract fixtures.

web
    Strict TypeScript, Monaco configuration, generated protocol types, bridge
    client, and local web assets.

features and repository
    Installable runtime/source features and signed p2 repository. The runtime
    feature contains core, bridge, web, and UI bundles.

tests
    Core/property tests, PDE/OSGi integration tests, browser tests, and
    compatibility smoke tests.
```

Dependency direction is `ui -> bridge -> core`; UI may also use core ports
directly. Core must never depend on bridge or UI.

The bridge's JSON runtime is one privately shaded embedded jar. It is present
on the bridge `Bundle-ClassPath`, is not exported, preserves licenses/service
descriptors, and is verified after p2 installation. Its original JSON package
names are private bundle-classpath content and must be neither imported nor
exported in the manifest. Do not turn ordinary Maven dependencies into
undeclared OSGi runtime assumptions.

Add and keep automated source, bytecode, manifest, and POM checks that reject
these dependencies from core:

```text
org.jkiss.
org.eclipse.
org.osgi.
org.eclipse.swt.
com.google.gson.
com.fasterxml.jackson.
```

An OSGi manifest for the core bundle is allowed; core production Java source
must remain platform-independent.

## 6. Required core interfaces and names

Do not rename these contracts without an accepted ADR and migration plan:

```java
public interface DBeaverEditorAdapter {
    DocumentPort document();
    SelectionPort selection();
    UndoPort undo();
    CommandPort commands();
    PresentationPort presentation();
    MutationProbePort mutationProbe();
    CapabilityReport probeCapabilities();
}

public interface DocumentPort {
    DocumentSnapshot snapshot();
    ApplyResult apply(EditBatch batch);
}

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

public interface CommandPort {
    CommandResult save(RevisionBarrier barrier);
    CommandResult format(RevisionBarrier barrier);
    CommandResult execute(ExecuteRequest request, RevisionBarrier barrier);
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

The approved session states are:

```text
NEW
PROBING
LOADING
HANDSHAKING
SYNCING
READY
RESYNCING
DEGRADED
FAILED
DISPOSED
```

Use Java 21 records and sealed interfaces for immutable domain messages.
Generated TypeScript must live under its generated directory and must not be
hand-edited. The original closed JSON Schema is the only validation contract.
Java deliberately uses one small handwritten bridge-private `WireEnvelope`;
validate the original schema before an exhaustive handwritten `kind` mapper
constructs core values. Every root union branch must be a complete closed
object; do not use an `allOf` envelope layout that causes the pinned TypeScript
generator to emit optional discriminants or an open index signature.
Contract tests must reflect the envelope fields, compare the mapper's
supported kinds with the source schema exactly, and pass one valid fixture per
branch through both validators and the Java mapper with exact core-record
assertions. Do not introduce a weakened Java code-generation schema or
annotation processor.

All canonical document messages carry `documentStamp`. If
`IDocumentExtension4` is unavailable, the compatibility probe must fail the
critical mutation capability; never synthesize a trustworthy stamp.

`EditBatch` contains `readinessEpoch`, `baseRevision`, `baseDocumentStamp`,
monotonic `clientSequence`, and at most 1,024 edits.
`RevisionBarrier` contains readiness epoch, revision, document stamp,
acknowledged edit sequence, and acknowledged selection sequence. Do not weaken
either contract for convenience.

Presentation changes and fallback go only through `PresentationPort`. No
controller outside the version-specific DBeaver adapter may reach into
`SQLEditor` or a presentation manager.

The synchronous DBeaver `canHidePresentation` and `canShowPresentation`
callbacks are part of the switching boundary. An external/native switch first
freezes the source, schedules the asynchronous flush/barrier transaction, and
returns `false`. Only the switch controller may arm a session- and
target-bound one-shot permit before its later public
`showExtraPresentation(...)` call; the callback consumes that permit and
returns `true`. Clear it in `finally`. A direct native menu/toolbar switch must
not bypass this gate.

## 7. Coding conventions

### Java

- Java 21.
- Maven 3.9.16 and Tycho 5.0.3 only.
- Constructor injection; no service locator.
- No mutable static editor, browser, document, or session references.
- Model `EditorLifetimeOwner -> MonacoActivation -> activation resources`
  explicitly; child disposal cannot dispose parent recovery/breaker state.
- One class has one primary responsibility.
- Prefer immutable records, enums, and sealed event types.
- Keep DBeaver objects out of background jobs. Pass immutable snapshots and
  revision values instead.
- All DBeaver/SWT access occurs on the SWT UI thread.
- Never call `syncExec` from a `BrowserFunction`.
- Disposal is idempotent, explicit, and in reverse acquisition order.
- `DISPOSED` is an absorbing session state; late callbacks have no effects.
  `FAILED` emits fallback effects once and then absorbs all events except one
  final disposal.
- Catch expected typed failures at boundaries. Catch `LinkageError` only at
  the compatibility-adapter boundary. Do not broadly catch `Throwable`.

### TypeScript

- `strict: true`; do not use `any`.
- Node 24.18.1 and npm 11.16.0 are build-time only. From Task 3 onward,
  `./mvnw verify` owns `npm ci`, protocol check, lint, unit test, and web build
  for a clean checkout.
- Keep generated TypeScript bridge types separate from handwritten code.
- Treat generated declarations as untrusted until the semantic contract proves
  all envelope fields and kind/payload pairs are required and rejects open
  index signatures, `any`, and `unknown`. Regeneration/diff alone is not a
  sufficient protocol check.
- Monaco-local commands stay local. Host commands go through the typed
  allowlist.
- Every asynchronous intelligence result carries the document revision and is
  discarded if stale.
- Dispose every Monaco model, subscription, worker, and DOM listener.

### General

- Respect `.editorconfig` and `.gitattributes`; do not introduce mixed line
  endings or incidental formatting churn.
- Prefer focused files over broad utility classes.
- Do not introduce a generic event bus.
- Error values use stable reason codes, not serialized exceptions.
- Comments explain invariants or non-obvious constraints, not syntax.
- Do not leave placeholder implementations or disabled tests in a completed
  task.

## 8. Test-first workflow

For behavior changes:

1. Add the smallest failing test.
2. Run the focused test and record the expected failure.
3. Implement the minimum behavior.
4. Run the focused test.
5. Run the relevant module suite.
6. Run the repository verification required by the plan task.
7. Inspect the diff for unrelated changes.

Planned verification commands, once the scaffold task creates them:

```bash
./mvnw -B verify
npm --prefix web ci
npm --prefix web run lint
npm --prefix web test
npm --prefix web run build
```

Tycho `eclipse-test-plugin` tests execute in the integration-test/verify
lifecycle. Every focused Maven PDE test command must therefore terminate in
`verify`; a terminal bare Maven `test` is forbidden because it can produce a
false green without running Tycho Surefire.

Default `./mvnw verify` runs only headless/mock suites and contains no skipped
or disabled native tests. Real-display SWT tests are separate reactor modules
activated by `-Pnative-ui`; full installed-product tests are activated by
`-Pnative-e2e`. Both profiles require an absolute existing
`-Ddbeaver.product.path=...`, resolve a dedicated native test target against
that product, and run under a real native display. Performance gates live
behind `-Pperformance` but use the same checksum-pinned product, native target,
absolute product path, and real display for Java bridge/document latency;
standalone Playwright may measure only render/scroll behavior. Test-only
JUnit/jqwik/H2 bundles must never enter the runtime feature or p2 repository.

Before running a documented command, inspect the current files and confirm that
the command exists. If an earlier task has not created it, report the missing
prerequisite instead of inventing a replacement.

Critical invariant tests include:

- equal text after every acknowledged edit and revision barrier;
- matching epoch, revision, document stamp, and edit sequence after every
  host-to-web edit acknowledgement;
- acknowledged edit and selection sequences before every host command;
- UTF-16 surrogate-pair offsets;
- descending multi-cursor edits in one compound undo;
- canonical patches absent from Monaco undo history;
- no echo after canonical document events;
- stale response rejection;
- one resync followed by circuit-breaker fallback;
- no editable state before snapshot, mutation/undo, and command-channel proofs;
- no snapshot readiness without both acknowledgement and recovery headroom;
- stale readiness epochs cannot enable editing or revoke the current epoch;
- exact guard loss in `SYNCING` cannot later combine with delayed facts;
- post-ready document advancement preserves same-epoch mutation/guard proofs;
- recovery-capacity rejection before any canonical mutation;
- native editor survival after Browser or bridge failure;
- Native↔Monaco switching without replacing the canonical document;
- native presentation commands vetoed until the asynchronous switch barrier
  completes and a one-shot permit is consumed;
- honest Browser-crash recovery provenance;
- no snapshot authorization before a matching committed resync handle/capture
  phase, including late/duplicate/wrong callbacks;
- no duplicate physical command guard during post-resync rebind;
- external canonical queue count and aggregate-byte overflow without retained
  accounting leaks;
- activation switch/fallback retains SQL-editor breaker/recovery ownership and
  uses a fresh asset lease on reactivation;
- no retained listener/session after repeated open/close;
- bridge rejection of invalid session/epoch, command, schema, edit count, and
  payload size;
- one exact Java mapping assertion for every protocol union branch;
- max-safe integers accepted and max-safe-plus-one rejected in Java and
  TypeScript;
- no dynamic schema compilation under the production CSP.

## 9. Git and pull-request discipline

- Work on a task branch; never commit directly to `main`.
- Keep the worktree clean before and after the task.
- Do not overwrite or revert unrelated user changes.
- One plan task should produce one independently reviewable pull request.
- Use small commits at meaningful test-green points.
- Do not combine formatting, dependency upgrades, and behavior unless the plan
  task explicitly requires all three.
- Link the plan task and relevant ADRs in the pull request.
- Use the repository pull-request template.
- A plan task is not complete until required verification passes or an exact
  blocker is documented.
- Do not begin the next plan task in the same branch or cloud run. The owner or
  orchestrator supplies the next prompt after reviewing the draft PR.

Recommended commit prefixes:

```text
build:
docs:
test:
feat:
fix:
refactor:
chore:
```

## 10. Architectural changes

Do not make architectural decisions silently.

If implementation evidence contradicts the approved design:

1. Stop the current task before broad refactoring.
2. Record the observed API, manifest, log, or test evidence.
3. Describe at least two options and their compatibility/data-safety impact.
4. Propose a new or superseding ADR.
5. Wait for owner approval.

Reflection is not a general compatibility strategy. If unavoidable, confine it
to one version-specific adapter, validate it with capability probes, and
document it in an ADR.

## 11. Stop conditions

Stop and request a decision when:

- a required public DBeaver API differs from the design;
- the pinned DBeaver target cannot be resolved reproducibly;
- the exact public presentation/command/selection/undo API captured in Task 1
  cannot be proved against the prepared product;
- the change requires a new runtime dependency;
- a requested change would make Monaco authoritative;
- a command cannot be routed through native DBeaver behavior;
- a security audit reports an unresolved production vulnerability;
- a cross-platform browser behavior requires platform-specific semantics;
- signing secrets or strict signature verification are unavailable for a
  release task;
- passing tests would require weakening a documented invariant;
- the task would touch files outside its declared scope.

## 12. Definition of done

A task is done only when:

- its acceptance criteria and interfaces match the implementation plan;
- focused tests were observed failing before implementation when applicable;
- all required focused and repository-level checks pass;
- no generated file was manually edited;
- no prohibited imports or sensitive logs were added;
- disposal and failure paths were tested where relevant;
- documentation and ADRs match behavior;
- the pull request contains verification evidence and known limitations.

## 13. Mandatory final report

End every implementation run with:

```markdown
## Task
Plan task and branch/PR.

## Changed
Files and behavior changed.

## Evidence
Exact commands run and PASS/FAIL result.

## Architecture check
Canonical document, undo ownership, API boundary, fallback, security, and
disposal impact.

## Remaining
Known limitations or blockers. State “None” only when verified.

## Next
The next plan task, but do not start it automatically.
```

## 14. Public-link hygiene

Do not place internal ChatGPT or Codex task, chat, conversation, session,
workspace, or share URLs in public pull requests, issues, comments, commit
messages, logs, artifacts, or repository documentation. Public links to normal
official OpenAI product documentation are allowed. Use GitHub Issue, pull
request, Actions-run URLs, and commit SHAs as public implementation evidence.
