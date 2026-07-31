# ADR 0007: Bound recovery before mutation

## Status

Accepted — 2026-07-31

## Context

The host recovery journal must retain every validated batch that can affect the
canonical document. A journal that silently evicts unacknowledged edits can no
longer explain or reconstruct host-received state. Applying first and
discovering a capacity failure afterward would make safe fallback impossible.

## Decision

Protocol and recovery limits are named constants and constructor-validated:

- maximum bridge envelope: 64 MiB of UTF-8 bytes;
- maximum normal edit batch: 8 MiB of UTF-8 bytes;
- maximum document or recovery text: 16 Mi UTF-16 code units;
- maximum recovery journal: 32 MiB and 2,048 entries.

The journal owns a bounded host-known checkpoint plus later validated entries.
It may compact an acknowledged prefix into that checkpoint. It never evicts a
pending or failed entry.

Before mutating `IDocument`, the controller validates the batch and atomically
reserves journal capacity. If compaction cannot make room, it does not begin a
compound change and returns `RECOVERY_CAPACITY_EXCEEDED`. Monaco becomes
read-only. If the Browser remains live, the user may request a bounded typed
recovery export; the UI also offers an explicit switch to Native using the
unchanged canonical document. Recovery text is never applied automatically.

The 64 MiB envelope limit deliberately accommodates a worst-case encoded
16-million-code-unit recovery response plus schema overhead. Per-kind limits
still reject oversized ordinary edit batches.

External canonical changes have a separate exact-segment queue capped at both
256 entries and 64 MiB of conservatively counted retained UTF-16/metadata.
Capacity is reserved with checked arithmetic before copying the replaced and
inserted segments. Either overflow freezes the projection and requests
correlated recovery capture; it never drops/coalesces changes or creates a raw
candidate that could authorize resync.

## Consequences

- Any accepted canonical mutation has a corresponding host recovery record.
- Capacity exhaustion is a stable, testable failure rather than silent data
  loss.
- Documents larger than the bounded text limit remain usable in Native but
  cannot enter editable Monaco in this release.
- Memory use is bounded. Monaco-activation disposal transfers unresolved
  material to the SQL-editor owner; explicit resolution/discard or SQL-editor
  close releases it.

## Rejected alternatives

- Evict the oldest entry: rejected because it may be unacknowledged.
- Apply then record: rejected because recovery capacity is no longer atomic
  with canonical mutation.
- Unbounded journal: rejected because editor sessions could exhaust the JVM.
