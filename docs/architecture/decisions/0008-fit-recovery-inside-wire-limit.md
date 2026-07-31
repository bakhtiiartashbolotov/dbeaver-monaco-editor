# ADR 0008: Fit recovery inside the wire limit

## Status

Accepted — 2026-07-31

Amends the text-size constant in ADR 0007.

## Context

ADR 0007 allowed 16 Mi UTF-16 code units inside a 64 MiB UTF-8 JSON envelope.
A code unit may require a six-byte JSON escape. Sixteen million such units can
therefore exceed the envelope before metadata, contradicting the promise that
every supported recovery value is representable.

## Decision

Keep the 64 MiB bridge-envelope, 8 MiB normal-edit-batch, 32 MiB journal, and
2,048-entry limits. Reduce maximum document/recovery text to 10 Mi UTF-16 code
units. At six encoded bytes per unit, the worst-case text occupies 60 MiB and
leaves bounded room for the typed envelope.

The journal's 32 MiB accounting includes its retained checkpoint and every
pending, failed, or acknowledged-but-not-yet-compacted entry.

## Consequences

- The required 10 MiB ASCII SQL fixture remains supported.
- Every accepted recovery value can pass the outer bridge-size validator.
- Larger documents remain fully usable in Native but Monaco fails closed
  before accepting edits.

## Rejected alternatives

- Raise the envelope without a measured need: rejected because it increases
  attack and allocation bounds.
- Permit text that cannot be serialized: rejected because runtime behavior
  would depend on character distribution.
