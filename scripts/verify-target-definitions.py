#!/usr/bin/env python3
"""Validate the two closed Task 1 target definitions."""

from pathlib import Path
import sys
import xml.etree.ElementTree as ET

EXPECTED_DIRECTORY = {
    "type": "Directory",
    "path": "${project_loc:io.github.bakhtiiartashbolotov.dbeaver.monaco.target}/../../.cache/dbeaver-26.1.0/dbeaver",
}
EXPECTED_TEST_DIRECTORY = {
    "type": "Directory",
    "path": "${project_loc:io.github.bakhtiiartashbolotov.dbeaver.monaco.test.target}/../../.cache/dbeaver-26.1.0/dbeaver",
}
EXPECTED_MAVEN = {
    "type": "Maven",
    "includeDependencyDepth": "infinite",
    "includeDependencyScopes": "compile,runtime",
    "includeSource": "false",
    "missingManifest": "error",
}
EXPECTED_ROOTS = {
    ("org.junit.jupiter", "junit-jupiter-api", "5.13.4"),
    ("org.junit.jupiter", "junit-jupiter-engine", "5.13.4"),
    ("org.junit.platform", "junit-platform-launcher", "1.13.4"),
    ("org.junit.platform", "junit-platform-suite-api", "1.13.4"),
    ("org.junit.platform", "junit-platform-suite-engine", "1.13.4"),
}


def fail(message: str) -> None:
    raise SystemExit(message)


def locations(path: Path) -> list[ET.Element]:
    root = ET.parse(path).getroot()
    container = root.find("locations")
    if container is None:
        fail(f"target has no locations: {path}")
    return list(container)


def exact_attributes(element: ET.Element, expected: dict[str, str], label: str) -> None:
    if element.attrib != expected:
        fail(f"unexpected {label} attributes: {element.attrib}")


def main() -> None:
    if len(sys.argv) != 3:
        fail(f"usage: {sys.argv[0]} <production-target> <test-target>")
    production = locations(Path(sys.argv[1]))
    if len(production) != 1:
        fail("production target must contain exactly one location")
    exact_attributes(production[0], EXPECTED_DIRECTORY, "production Directory")
    if list(production[0]):
        fail("production Directory location must be empty")

    test = locations(Path(sys.argv[2]))
    if len(test) != 2:
        fail("test target must contain exactly two locations")
    directories = [entry for entry in test if entry.attrib.get("type") == "Directory"]
    maven = [entry for entry in test if entry.attrib.get("type") == "Maven"]
    if len(directories) != 1 or len(maven) != 1:
        fail("test target requires exactly one Directory and one Maven location")
    exact_attributes(directories[0], EXPECTED_TEST_DIRECTORY, "test Directory")
    exact_attributes(maven[0], EXPECTED_MAVEN, "test Maven location")
    dependencies = maven[0].find("dependencies")
    if dependencies is None or list(maven[0]) != [dependencies]:
        fail("test Maven location must contain only dependencies")
    roots = []
    for dependency in dependencies.findall("dependency"):
        if [child.tag for child in dependency] != ["groupId", "artifactId", "version"]:
            fail("Maven root must contain exactly groupId, artifactId, version")
        roots.append(tuple(dependency.findtext(name, "") for name in ("groupId", "artifactId", "version")))
    if len(roots) != len(set(roots)):
        fail("duplicate Maven test root")
    if set(roots) != EXPECTED_ROOTS:
        fail(f"unexpected Maven test roots: {sorted(set(roots) ^ EXPECTED_ROOTS)}")
    print("tracked production and test target definitions are closed and exact")


if __name__ == "__main__":
    main()
