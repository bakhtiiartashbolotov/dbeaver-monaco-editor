# ADR 0009: Gate editing on recovery headroom

## Status

Accepted — 2026-07-31

Amends the snapshot-readiness meaning in ADR 0005 and the size guarantees in
ADRs 0007–0008.

Amended by ADR 0010: readiness evidence is scoped by epoch and snapshot and
recovery-checkpoint acknowledgements are stored as distinct facts.

## Context

A document may satisfy the 10 Mi UTF-16 protocol limit yet require almost
60 MiB when JSON-escaped. It fits the 64 MiB bridge envelope but not the
32 MiB recovery journal. Even a checkpoint that fits is not sufficient if it
leaves no room for the next valid 8 MiB edit batch and bounded journal-entry
metadata.

Waiting until the first canonical mutation to discover this condition is
data-safe, because reservation still occurs first, but produces a poor and
misleading editing gate: Monaco may accept local input and immediately freeze.

## Decision

Protocol eligibility and recovery eligibility are separate.

- `MAX_TEXT_UTF16_CODE_UNITS` remains 10 Mi code units.
- `MAX_JOURNAL_ENTRY_METADATA_UTF8_BYTES` is 64 KiB. Schema string lengths and
  the canonical journal-entry representation are bounded so property tests can
  prove this is an upper bound.
- A canonical checkpoint is recovery-eligible only when overflow-safe,
  deterministic accounting proves:

```text
checkpointWireBytes
  + MAX_EDIT_BATCH_UTF8_BYTES
  + MAX_JOURNAL_ENTRY_METADATA_UTF8_BYTES
  <= maxJournalWireBytes
```

The session's document-readiness fact is created only when a canonical
snapshot acknowledgement and a distinct recovery-checkpoint fact match the
same epoch/revision/stamp and this headroom rule. Evidence from different
snapshots never combines. Check it before any `MutationChannelReady` can
contribute to editable readiness, after an external canonical replacement,
and after each acknowledgement/compaction before the host reports that
further input remains eligible.

Every host-to-web edit acknowledgement (`document.ack`) exposes a typed
`recoveryEligible` value.
When it is false, the web projection stops accepting further edits and the
session enters explicit recovery/fallback with
`RECOVERY_CAPACITY_EXCEEDED`. Already in-flight Browser-only text keeps the
same honest export/provenance rules as other undelivered input.

Per-batch capacity reservation remains mandatory as the final atomic barrier
before changing `IDocument`; eligibility is not a substitute for reservation.

## Consequences

- A 10 MiB ASCII SQL document remains editable because its checkpoint leaves
  more than one maximum-batch slot.
- Some highly escaped documents below the code-unit limit remain viewable in
  read-only Monaco but editable only in Native.
- The UI can explain protocol size separately from recovery headroom.
- External canonical growth can revoke Monaco editing before another host
  mutation is accepted.

## Rejected alternatives

- Increase the journal to match every worst-case bridge value: rejected
  because it materially raises per-editor memory bounds.
- Lower the protocol text limit to the worst-case journal size: rejected
  because it would unnecessarily exclude ordinary 10 MiB ASCII SQL.
- Rely only on per-batch rejection: rejected because the first user edit could
  discover a known checkpoint incompatibility.
