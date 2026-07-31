# ADR 0002: Eclipse IDocument is canonical

## Status

Accepted — 2026-07-31

## Context

Monaco requires an `ITextModel`, while DBeaver's save, dirty-state, selection,
undo, SQL execution, and external resource updates operate on Eclipse
`IDocument`. Treating both as writable authorities creates conflicts and two
undo histories.

## Decision

`IDocument` is the only canonical text model. Monaco is an incrementally
synchronized projection.

- Bridge offsets use UTF-16 code units.
- Every change includes a base revision, client sequence, session ID, and
  document stamp.
- Monaco multi-edits are applied to `IDocument` in descending offset order
  inside one `IRewriteTarget` compound change.
- Origin guards suppress echo.
- Eclipse's undo manager is authoritative; Monaco undo and redo route to it.
- Semantic selection carries revision, document stamp, and a monotonic
  sequence acknowledged by Java.
- Save, execute, format, and presentation switching require a barrier over
  revision, document stamp, and acknowledged selection sequence.
- A mismatch permits one full resync from `IDocument`, never the reverse; the
  allowance is not reset within the same SQL-editor lifetime, including after
  switching Native→Monaco again.

## Consequences

- DBeaver commands always read current canonical SQL.
- Native and Monaco presentations see the same editor input and dirty state.
- A bounded host journal can recover only edit batches that reached Java.
  Keystrokes lost inside a crashed Browser before delivery are explicitly not
  recoverable; no recovery path may silently replace the saved document.
- Synchronization and undo behavior require property and cross-platform tests.

## Rejected alternatives

- Monaco as canonical model: rejected because DBeaver would observe stale text.
- Last-writer-wins merge: rejected because it can silently lose SQL.
- Independent Monaco and Eclipse undo stacks: rejected because histories
  diverge after external edits or presentation switching.
