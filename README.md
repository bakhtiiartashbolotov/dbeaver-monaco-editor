# DBeaver Monaco Editor

An Apache-2.0 DBeaver Community extension that adds a Monaco-based editing
presentation to the existing SQL Editor while keeping DBeaver responsible for
documents, connections, SQL execution, transactions, and result grids.

> Status: approved architecture and cloud-development bootstrap. Production
> code has not been implemented yet.

## MVP

- Switch each SQL Editor between `Native` and `Monaco`.
- Preserve VS Code-style editing behavior: `Ctrl+D`/`Cmd+D`, multiple cursors,
  native wheel scrolling, minimap, find, and familiar navigation.
- Save through DBeaver's canonical document.
- Execute the current or primary selected SQL with DBeaver's native command.
- Render results in DBeaver's native result grid.
- Run on Windows, macOS, and Linux using the system SWT Browser.

## Non-goals for the first vertical slice

- Replacing DBeaver's SQL execution engine or result UI.
- Forking or patching DBeaver.
- Bundling Chromium, Electron, Node.js, or a remote web service at runtime.
- Reproducing DBeaver-aware completion, diagnostics, hover, or a second
  formatting engine in the first release. A safe public native format command
  may be reused through the same guarded barrier.

## Planned repository layout

```text
.
├── AGENTS.md
├── bundles/
│   ├── io.github.bakhtiiartashbolotov.dbeaver.monaco.core/
│   ├── io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge/
│   └── io.github.bakhtiiartashbolotov.dbeaver.monaco.ui/
├── third-party/
│   └── io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge-json-runtime/
├── releng/
│   ├── io.github.bakhtiiartashbolotov.dbeaver.monaco.target/
│   ├── io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target/
│   └── io.github.bakhtiiartashbolotov.dbeaver.monaco.native.test.target/
├── protocol/
│   ├── schema/
│   └── fixtures/
├── web/
├── features/
│   ├── io.github.bakhtiiartashbolotov.dbeaver.monaco.feature/
│   └── io.github.bakhtiiartashbolotov.dbeaver.monaco.source.feature/
├── repository/
├── tests/
└── docs/
    ├── architecture/
    └── superpowers/
        ├── specs/
        └── plans/
```

The core bundle contains no DBeaver, Eclipse, SWT, or JSON implementation
dependencies. The bridge bundle owns schema validation and JSON packaging.
All platform calls are isolated in the UI adapter.

## Start here

1. Read [AGENTS.md](AGENTS.md).
2. Read the
   [approved design](docs/superpowers/specs/2026-07-31-dbeaver-monaco-editor-design.md).
3. Read the [architecture decisions](docs/architecture/README.md).
4. Follow the
   [bootstrap and vertical-spike plan](docs/superpowers/plans/2026-07-31-bootstrap-and-vertical-spike.md)
   one task and one pull request at a time.
5. Use [cloud-development.md](docs/cloud-development.md) to create and connect
   the repository.
6. Use [agent-workflow.md](docs/agent-workflow.md) for copy-paste prompts and
   review gates.

## Baseline toolchain

| Component | Baseline |
| --- | --- |
| Java | 21 |
| Maven/Tycho | Maven 3.9.16 wrapper / Tycho 5.0.3 |
| Node.js/npm | 24.18.1 / 11.16.0, build-time only |
| Monaco Editor | 0.56.0 |
| DBeaver CE | minimum 26.1.0; verify 26.1.3 |
| Minimum compile platform | Eclipse 2026-03, matching DBeaver 26.1.0 |
| License | Apache License 2.0 |

The first implementation task must build against a checksum-pinned DBeaver
26.1.0 product installation. The public versioned p2 URL is not used because
it is unavailable; no UI work starts before the immutable-baseline gate.

## Contribution workflow

- One numbered implementation-plan task per branch and pull request.
- Use tests first for behavior.
- Keep pull requests small enough to review against one acceptance gate.
- Do not introduce DBeaver internal APIs or silently change an ADR.
- Record exact verification commands and outcomes in every pull request.

## License

Licensed under the [Apache License 2.0](LICENSE).
