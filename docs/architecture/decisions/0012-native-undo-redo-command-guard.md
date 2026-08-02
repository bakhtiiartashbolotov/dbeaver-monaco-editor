# ADR 0012: Guard native Undo/Redo direct-action routes

- Status: Proposed
- Date: 2026-08-01
- Decision owners: repository owner and maintainers

## Context

DBeaver 26.1.0 exposes Undo and Redo through command-handler routes and direct
Eclipse `IAction` routes. `BasicTextEditorActionContributor` installs editor
actions with `IActionBars.setGlobalActionHandler`; `ActionFactory` creates
retarget actions; `RetargetAction.run` and `runWithEvent` invoke the captured
action directly; and `AbstractTextEditor` contributes Undo directly to its
context menu. An action definition ID alone does not force those calls through
`IHandlerService`.

The approved design requires every native mutating surface to enter the same
Monaco freeze/flush/barrier guard. Task 7's handler-only assumption is therefore
not proven for the pinned baseline.

## Proposed options

### 1. Scoped public action/action-bars proxy guard

Install activation-scoped public `IAction` proxies for editor actions and
`IActionBars` global handlers, cover retargeted Edit/context-menu, toolbar, and
keybinding surfaces, and restore the exact captured actions in reverse order on
deactivation or disposal. Feasibility must prove atomic installation,
restoration, retarget refresh, no stale captured action, and one physical guard
per activation.

### 2. Upstream interception hook or newer minimum baseline

Request a public DBeaver interception API covering all mutation routes, or
raise the minimum supported baseline only after a newer checksum-pinned product
proves such an API. This has compatibility and release-timing costs but avoids
fragile action replacement.

### 3. Fail-closed Native-only behavior

Keep Monaco non-editable or unavailable on baselines where one atomic guard
cannot be proved. Native SQL editing remains usable. This is safest for data
integrity but withholds editable Monaco functionality.

## Status and consequences

No option is accepted by this ADR. Owner feasibility review is required before
Task 7. Until then, Undo/Redo and Format are independent fail-closed blockers
for editable Monaco. Pure-core, non-editable Task 2 is not blocked after Task 1
is merged.
