# ADR 0003: Use the system SWT Browser

## Status

Accepted — 2026-07-31

## Context

Monaco is a browser editor. Bundling Chromium would increase binary size,
platform packaging, patch responsibility, and attack surface. DBeaver already
uses SWT Browser-based views.

Monaco workers require HTTP semantics rather than a `file://` page.

## Decision

Use the system SWT Browser on Windows, macOS, and Linux. Serve ESM Monaco and
all web assets from a process-local server bound to the literal IPv4 bytes for
`127.0.0.1` on a random port, without hostname resolution.

- Assets are bundled in the plugin; runtime CDN access is forbidden.
- Every Monaco activation acquires a fresh lease that generates, owns, and
  destroys an unguessable token;
  callers cannot supply one.
- Apply a strict Content Security Policy.
- Reject external navigation and unexpected origins.
- The server is process-scoped and reference-counted; Monaco activations own
  leases, not the SQL-editor lifetime or server singleton. Leases/tokens are
  never reused on switch-back.
- Probe Browser, worker, clipboard, keybinding, and bridge behavior before
  enabling Monaco.

## Consequences

- Runtime remains smaller and uses OS-maintained browser components.
- Browser behavior must be tested on all supported operating systems.
- A missing or incompatible Browser backend disables Monaco while leaving the
  native editor available.
- Node.js is needed only to build static assets.

## Rejected alternatives

- Bundled Chromium/CEF: rejected for packaging and security maintenance cost.
- Electron editor process: rejected because it duplicates lifecycle and IPC.
- `file://` assets: rejected because Monaco web workers and security controls
  require a local HTTP origin.
