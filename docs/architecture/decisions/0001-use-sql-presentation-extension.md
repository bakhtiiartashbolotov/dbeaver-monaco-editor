# ADR 0001: Use the SQL presentation extension

## Status

Accepted — 2026-07-31

## Context

The plugin needs VS Code-like editing inside the existing DBeaver SQL Editor
while preserving native execution, transactions, results, and editor input.
A DBeaver fork would create a permanent merge burden and make p2 installation
and upgrades difficult.

DBeaver exposes `org.jkiss.dbeaver.sqlPresentation` and a public
`SQLEditorPresentation` contract for alternate presentations.

## Decision

Contribute `MonacoSQLPresentation` through
`org.jkiss.dbeaver.sqlPresentation`. Each SQL Editor offers a
`Native / Monaco` presentation switch. The plugin does not replace the editor
input or create a second SQL execution path.

The implementation may use public exported `SQLEditor` APIs but must not call
`ExtraPresentationManager` or any `.internal` package directly.

## Consequences

- DBeaver retains document providers, dirty state, execution contexts, command
  handlers, transactions, and results.
- Installation remains a normal Eclipse p2 extension.
- A change to the extension contract is isolated in the UI adapter.
- Features unavailable through public APIs must degrade or wait for a later
  DBeaver adapter; they must not be reached through scattered reflection.

## Rejected alternatives

- Fork DBeaver and replace its editor widget: rejected because of upgrade and
  distribution cost.
- Add an unrelated view/panel: rejected because it would duplicate editor
  input, selection, save, and lifecycle semantics.
- Replace execution with a custom JDBC layer: rejected because it would bypass
  DBeaver behavior and create data-safety risk.
