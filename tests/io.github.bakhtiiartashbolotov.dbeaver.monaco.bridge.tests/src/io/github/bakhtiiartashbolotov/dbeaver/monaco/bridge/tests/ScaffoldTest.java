package io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge.tests;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;

import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.osgi.framework.Bundle;
import org.osgi.framework.FrameworkUtil;

final class ScaffoldTest {
    private static final List<ExpectedBundle> EXPECTED_BUNDLES = List.of(
        new ExpectedBundle("junit-jupiter-api", "5.13.4"),
        new ExpectedBundle("junit-jupiter-engine", "5.13.4"),
        new ExpectedBundle("junit-platform-launcher", "1.13.4"),
        new ExpectedBundle("junit-platform-suite-api", "1.13.4"),
        new ExpectedBundle("junit-platform-suite-engine", "1.13.4"),
        new ExpectedBundle("junit-platform-suite-commons", "1.13.4")
    );

    @Test
    void exactTestPlatformIsResolved() {
        var context = FrameworkUtil.getBundle(getClass()).getBundleContext();
        for (var expected : EXPECTED_BUNDLES) {
            var matches = Arrays.stream(context.getBundles())
                .filter(bundle -> expected.symbolicName().equals(bundle.getSymbolicName()))
                .toList();
            assertEquals(1, matches.size(),
                () -> "Expected exactly one resolved bundle " + expected.symbolicName()
                    + ", found " + matches.size());
            var bundle = matches.getFirst();
            assertNotEquals(Bundle.INSTALLED, bundle.getState(),
                () -> expected.symbolicName() + " remained INSTALLED");
            assertNotEquals(Bundle.UNINSTALLED, bundle.getState(),
                () -> expected.symbolicName() + " was UNINSTALLED");
            assertEquals(expected.version(), bundle.getVersion().toString(),
                () -> "Unexpected version for " + expected.symbolicName());
        }
    }

    private record ExpectedBundle(String symbolicName, String version) {}
}
