# ADR 0010: Version readiness and flush barriers by epoch

## Status

Accepted — 2026-07-31

Amends ADRs 0002, 0004, 0005, 0006, and 0009.

## Context

Revision and document-stamp equality is not sufficient to distinguish two
full synchronization generations. A delayed message from before a resync can
have the same values as a new snapshot. Readiness facts bound directly to a
document revision also become inconsistent after the first successful edit:
the document advances, while the already proven mutation channel and live
command guard remain valid.

Native toolbar, menu, and keybinding commands introduce a second race. A
Monaco model event may already exist in the Browser but not yet have reached
the Java host when the native command is invoked. Checking only the host's
last known revision can therefore save, format, undo, or execute stale text.

## Decision

Each Monaco activation starts with `readinessEpoch = 1`, but the
circuit-breaker allowance belongs to the longer SQL-editor lifetime and is not
reset by reactivation. The first permitted full resync from `SYNCING`, `READY`,
or `DEGRADED` atomically consumes that allowance, freezes Monaco under the
source epoch, blocks the one physical command guard, revokes its logical
lease, and stores a correlated `CapturingRecovery` transaction.

Before any overwrite, a bounded recovery export is validated and committed to
the parent-owned store under the current activation/resync/source/request
tuple. Only that exact opaque committed-candidate handle may replace the
transaction with
`PreparingSnapshot(targetEpoch, handle, snapshotCaptureId)`, authorize the
checked epoch increment/readiness/sequence reset, and request one capture. A
prepared event must match all authorization fields; prepared-before-store,
wrong/late/duplicate callbacks cannot send a snapshot. The accepted event
clears the transaction and commits the reducer to `SYNCING` before its single
send effect, so a re-entrant Browser acknowledgement sees the correct state.
Readiness events are ignored during capture, and old-epoch events are ignored
afterward. Epoch, store, or capture failure fails closed without overwriting
the projection.

Every document, selection, session-mode, flush, and command payload carries
the epoch. Initial readiness combines a distinct web-to-host snapshot
acknowledgement with recovery checkpoint eligibility for the exact
`(epoch, revision, documentStamp)`. Mutation proof is epoch-bound. Command
readiness is an epoch-bound live guard lease with a unique lease ID.

After startup, an acknowledged Monaco edit or acknowledged canonical patch
uses `DocumentReadinessAdvanced` to replace the current document stamp
atomically. The synchronization controller accepts it only for its exact
canonical state and a strictly newer revision. It preserves mutation and
command facts from the same epoch. Headroom loss must match the stored current
stamp; command loss must match the current lease ID.
Loss of that exact stored lease is critical even in `SYNCING` before the other
facts arrive. During resync the same physical guard remains installed in
blocking mode and is atomically rebound to a new-epoch lease after capability
reproof; a second handler activation is forbidden.

Wire acknowledgements have non-interchangeable directions:

- `document.snapshotAck`: web to host, after exact snapshot application;
- `document.patchAck`: web to host, after exact non-undoing patch application;
- `document.ack`: host to web, after a Monaco edit reaches canonical text.

Integrated Monaco boots read-only. The host changes editability only through
typed `session.mode` messages. Before every web- or native-origin host command
and every presentation switch, the host sends a correlated flush request that
freezes the model. External canonical changes use the same coordinator and
send an incremental patch only when the drained web barrier exactly matches
the retained pre-change canonical state; otherwise they enter resync/recovery.
The web client drains all dispatched edit and selection messages, waits for
their acknowledgements, and returns the full
epoch/revision/stamp/edit-sequence/selection-sequence barrier. Native code is
invoked only if the response and current canonical controller state match
exactly. Waiting never blocks the SWT thread.

Command requests also carry a monotonic command sequence. A bounded per-epoch
replay ledger has separate host-assigned `WEB` and `NATIVE` namespaces, returns
the cached full `EditorCommandResponse` (including applied barrier) for an
exact retry, and never invokes the native handler twice. Only the single-use
completion permit for the accepted request may populate that cache. Origin is
not client-controlled. Reusing a sequence or message ID with different
content fails closed.

## Consequences

- Delayed events cannot re-enable or disable a later synchronization
  generation, even if revision and document-stamp values repeat.
- Ordinary acknowledged edits advance readiness without rerunning capability
  probes.
- Native command latency includes an asynchronous flush transaction, but
  commands cannot observe Browser-local text that the host has not received.
- An external canonical patch may fall back to full resync when Browser-local
  edits race the native change; the projection is surfaced as recovery data
  rather than silently discarded.
- The protocol needs explicit snapshot/patch acknowledgements, session mode,
  and flush request/response kinds from its first stable version.
- Reducer and bridge tests must cover stale epochs, exact lease identity,
  post-ready advancement, and undelivered Browser events.

## Rejected alternatives

- Use only revision and document stamp: rejected because values may repeat
  across a resync generation.
- Bind mutation and command proof to every document revision: rejected because
  it would invalidate valid live capabilities after every edit.
- Trust the host's latest barrier when a native command arrives: rejected
  because Browser-local events may still be queued.
- Reuse one generic document acknowledgement in both directions: rejected
  because it makes initial snapshot, canonical patch, and edit confirmation
  impossible to validate independently.
