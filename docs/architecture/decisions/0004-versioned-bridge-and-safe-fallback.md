# ADR 0004: Version the bridge and fail closed

## Status

Accepted — 2026-07-31

## Context

The plugin crosses three changing boundaries: DBeaver/Eclipse APIs, the SWT
Browser backend, and Java↔TypeScript messages. Comparing only product version
strings cannot prove behavioral compatibility.

## Decision

Use one closed JSON Schema protocol source and generate the TypeScript
discriminated union and build-time Ajv standalone validator from it. Every
root union branch is a complete closed object; shared scalar definitions avoid
constraint drift without relying on an `allOf` layout that the pinned
TypeScript generator would weaken. Java uses one small handwritten
bridge-private envelope, validates the original closed union first, then maps
each `kind` and opaque payload manually and exhaustively to immutable core
variants. Contract tests compare every Java envelope branch and mapper kind
with the schema, and one canonical valid fixture per branch proves exact
payload-to-core mapping. This avoids a weakened derived schema and a processor
that cannot represent the union.

Every envelope includes exact protocol version, session ID, message ID, and a
schema-validated payload. All TypeScript-visible integers are bounded by
`Number.MAX_SAFE_INTEGER`; offsets and lengths also fit Eclipse int APIs. Ajv
schema compilation happens only during the build. Because Ajv standalone may
still reference CommonJS runtime helpers, a pinned direct esbuild step bundles
the intermediate and all helpers into self-contained ESM. The browser imports
only that result under the shared exact CSP with no `unsafe-eval` or dynamic
code generation. Ajv remains a production dependency/SBOM/license component
because helper code is embedded; generator and bundler tools remain
development-only.

Startup performs:

1. coarse product and OSGi version checks;
2. public API and functional capability probes;
3. Java↔web protocol handshake;
4. canonical snapshot and revision acknowledgement;
5. canonical mutation and compound-undo probes on a throwaway document made
   through the same adapter factory, never the user's SQL document;
6. transition to editable `READY`.

Protocol-major mismatch or missing critical capabilities prevents Monaco from
becoming editable. Optional features negotiate independently. Repeated bridge
or revision failure opens recovery and falls back to the native presentation.
Snapshot acknowledgement without a proven mutation channel remains read-only
in `SYNCING`.

All DBeaver calls are isolated behind `DBeaverEditorAdapter`. A future breaking
line receives another adapter instead of conditionals throughout the codebase.

## Consequences

- Compatible patch upgrades continue to work based on capability evidence.
- Optional API changes do not disable core editing.
- Unknown breaking upgrades cannot damage a document or prevent native DBeaver
  use.
- Supporting a genuinely changed public contract still requires a plugin
  release; architecture cannot guarantee unknown future binary compatibility.

## Rejected alternatives

- Product-version checks alone: rejected because behavior may change within a
  line.
- Reflection throughout the UI: rejected because it is unreadable and fails
  late.
- Best-effort editing after protocol mismatch: rejected because it risks stale
  or lost text.
