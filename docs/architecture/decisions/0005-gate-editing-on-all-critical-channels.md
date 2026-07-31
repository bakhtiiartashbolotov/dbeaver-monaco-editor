# ADR 0005: Gate editing on all critical channels

## Status

Accepted — 2026-07-31

Amends the startup sequence in ADR 0004.

## Context

ADR 0004 required snapshot and mutation/compound-undo probes before editable
`READY`. Native save and SQL execution are also critical capabilities, but
their routing is implemented after incremental synchronization. Enabling input
after only the mutation probe would create a period in which text can change
but native save, undo, or execution has not been proven safe.

## Decision

The session context stores three independent readiness facts:

1. canonical snapshot acknowledged;
2. real bridge mutation plus compound Eclipse undo proven on a throwaway
   document created through the adapter factory;
3. native save, undo, redo, statement, and script command definitions,
   barrier routing, and scoped command-guard activation proven.

`SnapshotAcknowledged` and `MutationChannelReady` remain read-only in
`SYNCING`. `CommandChannelReady` may enter `READY`, or optional-only
`DEGRADED`, only when all three facts are present. Events do not rely on the
implementation-task order.

`DBeaverEditorAdapter` exposes a `MutationProbePort`. Its
`ProbeDocumentLease` owns a hidden throwaway JFace document/viewer/undo
manager, exposes only `DocumentPort`, `SelectionPort`, and `UndoPort`, and is
always disposed. The user's SQL document and undo history are never used for
the probe.

Before their implementations exist, mutation, undo, command, and presentation
ports are explicit fail-closed `Unavailable*Port` values returning
`SESSION_NOT_READY`; they are not nullable or placeholder successes.

## Consequences

- A visible Monaco model cannot accept input that cannot yet be saved,
  executed, or undone through DBeaver.
- Tasks for snapshot and synchronization can merge safely while remaining
  demonstrably read-only.
- The adapter factory and probe lease need integration tests and strict
  disposal ownership.

## Rejected alternatives

- Enable editing after the mutation probe: rejected because native commands
  remain unproven.
- Probe against the user's document and undo stack: rejected because startup
  would mutate user state.
- Infer readiness from task number or object presence: rejected because it is
  not a runtime behavioral guarantee.
