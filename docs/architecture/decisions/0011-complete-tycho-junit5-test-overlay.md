# ADR 0011: Complete the Tycho JUnit 5 test overlay

## Status

Accepted — 2026-07-31

## Context

Task 1 originally named three Maven roots for its test-only target. During the
Tycho 5.0.3 `verify` lifecycle, `tycho-surefire-plugin` selected its JUnit 5
provider and failed before executing tests because its OSGi runtime requires
both `org.junit.platform.suite.api` and
`org.junit.platform.suite.engine`. Adding Suite API alone only advances the
failure to the missing Suite Engine package. The provider's resolved runtime
closure also requires `junit-platform-suite-commons`.

The production target must remain the exact checksum-pinned DBeaver product.
JUnit and Tycho test harness bundles must never contaminate production output.

## Decision

The separate test target retains the DBeaver directory and adds one Maven
location with `includeDependencyDepth="infinite"`,
`includeDependencyScopes="compile,runtime"`, no sources, and manifest errors
enabled. Its five exact roots are:

- `org.junit.jupiter:junit-jupiter-api:5.13.4`;
- `org.junit.jupiter:junit-jupiter-engine:5.13.4`;
- `org.junit.platform:junit-platform-launcher:1.13.4`;
- `org.junit.platform:junit-platform-suite-api:1.13.4`;
- `org.junit.platform:junit-platform-suite-engine:1.13.4`.

`junit-platform-suite-commons` 1.13.4 is required resolved runtime closure,
not an additional root. All JUnit Platform Suite, Jupiter, supporting JUnit,
and Tycho Surefire artifacts remain test-only. They never enter the production
target, runtime feature, generated p2 repository, or production SBOM.

## Consequences

All three PDE smoke-test bundles can execute under Tycho 5.0.3 and assert the
six expected JUnit bundle versions. Production resolution continues to ignore
POM dependencies and uses only the verified DBeaver target plus current-reactor
production artifacts. Repository checks reject test-only bundle leakage.

## Rejected alternatives

- Add only `junit-platform-suite-api`: rejected because the provider also has
  a mandatory Suite Engine import.
- Force a different Surefire provider: rejected because it diverges from
  Tycho 5.0.3's supported JUnit 5 PDE runtime.
- Use JUnit 4: rejected because Task 1 requires JUnit 5 smoke tests.
- Add Orbit or another p2 repository: rejected because it could inject an
  independent Eclipse platform and breaks the pinned-product target invariant.
- Disable or skip PDE tests: rejected because a green build must execute them.
- Use the aggregate `junit-platform-suite` artifact: rejected because it hides
  the provider's two exact runtime roots and weakens overlay reviewability.

## Migration

Task 1's plan and target definition are amended to the five roots above. No
production bundle, feature, or repository dependency changes are required.
