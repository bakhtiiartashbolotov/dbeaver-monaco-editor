# Architecture decisions

The approved design is
[`2026-07-31-dbeaver-monaco-editor-design.md`](../superpowers/specs/2026-07-31-dbeaver-monaco-editor-design.md).
ADRs record decisions that implementation agents must not change silently.

| ADR | Status | Decision |
| --- | --- | --- |
| [0001](decisions/0001-use-sql-presentation-extension.md) | Accepted | Add Monaco through DBeaver's SQL presentation extension |
| [0002](decisions/0002-idocument-is-canonical.md) | Accepted | Eclipse `IDocument` is the only canonical text model |
| [0003](decisions/0003-use-system-swt-browser.md) | Accepted | Use the system SWT Browser and local bundled assets |
| [0004](decisions/0004-versioned-bridge-and-safe-fallback.md) | Accepted | Negotiate a typed bridge and fail closed for Monaco |
| [0005](decisions/0005-gate-editing-on-all-critical-channels.md) | Accepted | Keep Monaco read-only until mutation, undo, and native command channels are proven |
| [0006](decisions/0006-serialize-presentation-switching.md) | Accepted | Veto native presentation switches until the shared asynchronous barrier completes |
| [0007](decisions/0007-bound-recovery-before-mutation.md) | Accepted | Reserve bounded recovery capacity before changing the canonical document |
| [0008](decisions/0008-fit-recovery-inside-wire-limit.md) | Accepted | Cap recovery text at 10 Mi code units so worst-case JSON remains bounded |
| [0009](decisions/0009-gate-editing-on-recovery-headroom.md) | Accepted | Require checkpoint plus one maximum edit batch to fit before enabling Monaco editing |
| [0010](decisions/0010-version-readiness-and-flush-barriers-by-epoch.md) | Accepted | Version readiness generations and drain Browser queues before native commands |
| [0011](decisions/0011-complete-tycho-junit5-test-overlay.md) | Accepted | Complete Tycho 5.0.3's test-only JUnit 5 runtime overlay |

## Changing a decision

Create a new numbered ADR that either amends or supersedes the old one.
Include implementation evidence, compatibility and data-safety effects,
rejected alternatives, and a migration plan. Do not edit an accepted ADR to
make history appear different.
