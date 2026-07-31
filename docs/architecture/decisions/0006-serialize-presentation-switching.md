# ADR 0006: Serialize presentation switching

## Status

Accepted — 2026-07-31

## Context

DBeaver's native presentation command calls public
`SQLEditor.showExtraPresentation(...)` directly. Its presentation manager then
calls synchronous `canHidePresentation` and `canShowPresentation` hooks. A
web-only command interceptor cannot protect this path, while flushing Monaco
document and selection acknowledgements is asynchronous.

## Decision

Every Native↔Monaco change is one `PresentationSwitchController` transaction
with explicit phases: `IDLE`, `FREEZING_SOURCE`, `VERIFYING_BARRIER`,
`ACTIVATING_TARGET`, `RESTORING_VIEW`, or `FAILED`.

An external/native switch request reaching either Monaco presentation hook:

1. freezes the source against new edits;
2. schedules the controller transaction after the current DBeaver callback;
3. returns `false` synchronously.

After flush and revision/stamp/selection barrier verification, the controller
arms an internal permit bound to the Monaco activation, target presentation, and
single activation. It then invokes the public adapter
`PresentationPort.activate(...)`. The relevant presentation hook consumes the
permit and returns `true`; the controller clears it in `finally`. The permit
cannot be supplied by a bridge caller, reused, or transferred to another
session or target.

Both direct plugin actions and DBeaver's native toolbar/menu/keybinding path
use this mechanism. No implementation calls the package-private
`ExtraPresentationManager`.

The DBeaver SQL-editor lifetime owns circuit-breaker and unresolved recovery
state across switches. Each Monaco activation owns a fresh Browser, bridge,
asset lease/token, replay/session state, and command guard. Confirmed switch
or fallback disposes that activation only after transferring unresolved
bounded recovery material to the parent; switching back creates fresh
activation resources and cannot reset the breaker.

## Consequences

- Native presentation UI cannot hide Monaco while acknowledgements are
  pending.
- Synchronous DBeaver callbacks remain non-blocking.
- Reentrancy and duplicate requests are explicit, testable controller states.
- Real-product tests must invoke DBeaver's own presentation command, not only
  the plugin's web action.

## Rejected alternatives

- Return `true` and flush afterward: rejected because pending projection edits
  could be abandoned.
- Block the SWT callback waiting on JavaScript: rejected because it can
  deadlock or freeze the UI.
- Intercept only the web switch action: rejected because native DBeaver UI
  reaches the presentation manager directly.
