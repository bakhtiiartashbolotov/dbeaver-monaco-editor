package io.github.bakhtiiartashbolotov.dbeaver.monaco.core.tests;
import static org.junit.jupiter.api.Assertions.assertEquals;
import org.junit.jupiter.api.Test;
import org.osgi.framework.FrameworkUtil;
final class ScaffoldTest {
 @Test void exactTestPlatformIsResolved() {
  var context = FrameworkUtil.getBundle(getClass()).getBundleContext();
  assertEquals("5.13.4", context.getBundle("junit-jupiter-api").getVersion().toString());
  assertEquals("5.13.4", context.getBundle("junit-jupiter-engine").getVersion().toString());
  assertEquals("1.13.4", context.getBundle("junit-platform-launcher").getVersion().toString());
 }
}
