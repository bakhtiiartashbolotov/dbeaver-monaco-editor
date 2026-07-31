## Plan task

- Plan: `docs/superpowers/plans/2026-07-31-bootstrap-and-vertical-spike.md`
- Task:
- Issue:
- Relevant ADRs:

## Scope

Describe the independently reviewable behavior delivered by this pull request.

## Changes

- <!-- List concrete changes. -->

## Verification evidence

List every command actually run and summarize its result. Do not write only
“tests pass”.

```text
command
PASS/FAIL — observed result
```

## Compatibility and fallback

- DBeaver targets exercised:
- Baseline archive SHA-256 verified:
- Operating systems/browser backends exercised:
- Critical capabilities affected:
- Behavior when the capability is unavailable:
- Native editor survival verified:

## Security and privacy

- [ ] No runtime CDN or external network dependency.
- [ ] No SQL, credentials, connection URLs, database object names, or raw
      bridge payloads added to logs.
- [ ] Bridge input is typed, session-bound, size-bounded, and allowlisted.
- [ ] Bridge JSON dependencies are private to the bridge bundle and their
      complete installed OSGi closure was tested.
- [ ] New dependencies include exact version, license, reason, audit result,
      and OSGi packaging impact.
- [ ] Changed workflows use explicit runner labels, full-commit-SHA action
      pins, least-privilege permissions, and no PR secrets or persisted
      checkout credentials.

## Architecture checklist

- [ ] `IDocument` remains canonical.
- [ ] Edits validate readiness epoch, base revision/stamp, sequence, byte
      limit, and maximum edit count.
- [ ] Commands freeze/drain the projection and validate the full
      epoch/revision/stamp/edit/selection barrier.
- [ ] Exact command retries use the replay ledger and cannot invoke a native
      handler twice; the completion permit caches the full response/barrier.
- [ ] Eclipse undo remains authoritative.
- [ ] Canonical patches do not enter Monaco undo history, and all exposed
      undo/redo surfaces route through Eclipse.
- [ ] No `.internal` DBeaver/Eclipse package is imported.
- [ ] `ExtraPresentationManager` is not called directly.
- [ ] Core production source has no DBeaver/Eclipse/SWT/JSON implementation
      imports.
- [ ] Failure disables Monaco safely without damaging native DBeaver behavior.
- [ ] Snapshot acknowledgement and recovery headroom jointly qualify the
      initial current-document readiness; mutation/compound-undo readiness
      cannot enable editing before the current-epoch native command guard also
      succeeds.
- [ ] Post-ready document advancement preserves only same-epoch capability
      proofs; stale epochs and wrong guard leases are rejected.
- [ ] The one automatic resync allowance cannot reset within a session.
- [ ] Resync increments/clears atomically, commits `SYNCING` before snapshot
      send, and emits the snapshot only once.
- [ ] The correlated resync transaction requires a committed handle plus
      matching capture identity; pre-store/wrong/late callbacks cannot send.
- [ ] A committed bounded Browser recovery candidate exists before resync can
      overwrite the projection; store/export failure cannot authorize it.
- [ ] External canonical patches freeze/drain and require an exact pre-change
      barrier before incremental application.
- [ ] The external canonical queue enforces both count and aggregate retained
      UTF-16/metadata budgets with leak-free reservation accounting.
- [ ] Recovery claims distinguish host-journaled edits from Browser-only text.
- [ ] Recovery capacity is reserved before canonical mutation; pending/failed
      journal entries cannot be evicted.
- [ ] Checkpoint plus one maximum edit batch and bounded metadata fit before
      Monaco accepts input; acknowledgements report `recoveryEligible`.
- [ ] Presentation switching/fallback uses `PresentationPort`, not a direct
      DBeaver presentation-manager call.
- [ ] Native `canHidePresentation`/`canShowPresentation` paths use the same
      asynchronous barrier and one-shot permit as plugin switch actions.
- [ ] New listeners, jobs, models, and server leases have tested disposal.
- [ ] `FAILED`/`DISPOSED` absorb late async callbacks without repeated effects.
- [ ] Switch/fallback uses a fresh activation lease/guard while preserving the
      SQL-editor-lifetime breaker and unresolved recovery owner.
- [ ] Release artifacts are signed and signature verification is recorded, or
      this PR is explicitly not a release.
- [ ] Compatibility evidence records the digest of the exact installed p2;
      release assembly publishes those same tested bytes.
- [ ] Stable compatibility has explicit PR/main/manual triggers and
      workflow-level `contents: read`; release `dist/` contains only its exact
      payload allowlist, never transport metadata or sidecars.

## UI evidence

Attach screenshots or a short recording for visible UI behavior. State
“No visible UI change” when not applicable.

## Known limitations

- <!-- State limitations or write “None”. -->

## Reviewer focus

Name the invariant or risk that deserves the closest review.
