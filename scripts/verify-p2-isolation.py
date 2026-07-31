#!/usr/bin/env python3
"""Verify the generated production p2 repository is a closed four-bundle set."""

from __future__ import annotations

from pathlib import Path
import stat
import sys
import xml.etree.ElementTree as ET
import zipfile

EXPECTED = {
    "io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge",
    "io.github.bakhtiiartashbolotov.dbeaver.monaco.core",
    "io.github.bakhtiiartashbolotov.dbeaver.monaco.ui",
    "io.github.bakhtiiartashbolotov.dbeaver.monaco.web",
}
TEST_MARKERS = (".tests", "junit", "surefire", "opentest4j", "apiguardian", "vintage")


def fail(message: str) -> None:
    raise SystemExit(message)


def closed_jars(directory: Path, label: str) -> list[Path]:
    if not directory.is_dir() or directory.is_symlink():
        fail(f"missing real {label} directory: {directory}")
    jars = []
    for entry in directory.iterdir():
        mode = entry.lstat().st_mode
        if not stat.S_ISREG(mode) or entry.suffix != ".jar":
            fail(f"unexpected {label} entry: {entry}")
        jars.append(entry)
    return sorted(jars)


def manifest_identity(bundle: Path) -> tuple[str, str]:
    try:
        with zipfile.ZipFile(bundle) as archive:
            text = archive.read("META-INF/MANIFEST.MF").decode("utf-8")
    except (KeyError, UnicodeDecodeError, zipfile.BadZipFile) as error:
        fail(f"unreadable bundle manifest: {bundle}: {error}")
    logical = []
    for line in text.replace("\r\n", "\n").split("\n"):
        if line.startswith(" ") and logical:
            logical[-1] += line[1:]
        else:
            logical.append(line)
    def header(name: str) -> str:
        values = [line.split(":", 1)[1].strip() for line in logical if line.startswith(f"{name}:")]
        if len(values) != 1:
            fail(f"bundle does not have exactly one readable {name}: {bundle}")
        return values[0]
    return header("Bundle-SymbolicName").split(";", 1)[0], header("Bundle-Version")


def compressed_xml(repository: Path, jar_name: str, xml_name: str) -> ET.Element:
    path = repository / jar_name
    if not path.is_file() or path.is_symlink():
        fail(f"missing repository metadata: {path}")
    try:
        with zipfile.ZipFile(path) as archive:
            return ET.fromstring(archive.read(xml_name))
    except (KeyError, ET.ParseError, zipfile.BadZipFile) as error:
        fail(f"invalid repository metadata {path}: {error}")


def assert_exact(actual: list[str] | set[str], label: str) -> None:
    values = list(actual)
    if len(values) != len(set(values)):
        fail(f"duplicate {label}: {values}")
    if set(values) != EXPECTED:
        fail(f"unexpected {label}: {sorted(set(values) ^ EXPECTED)}")
    for value in values:
        if any(marker in value.lower() for marker in TEST_MARKERS):
            fail(f"test-only {label}: {value}")


def main() -> None:
    if len(sys.argv) != 2:
        fail(f"usage: {sys.argv[0]} <repository-directory>")
    repository = Path(sys.argv[1])
    plugin_jars = closed_jars(repository / "plugins", "plugins")
    plugin_identities = [manifest_identity(bundle) for bundle in plugin_jars]
    plugin_bsns = [identity[0] for identity in plugin_identities]
    assert_exact(plugin_bsns, "plugin BSNs")
    if len(plugin_identities) != len(set(plugin_identities)):
        fail(f"duplicate plugin identities: {plugin_identities}")
    expected_identities = set(plugin_identities)

    feature_jars = closed_jars(repository / "features", "features")
    if len(feature_jars) != 1:
        fail(f"expected exactly one packaged feature, found {len(feature_jars)}")
    try:
        with zipfile.ZipFile(feature_jars[0]) as archive:
            feature = ET.fromstring(archive.read("feature.xml"))
    except (KeyError, ET.ParseError, zipfile.BadZipFile) as error:
        fail(f"invalid packaged feature: {error}")
    feature_plugins = [element.attrib.get("id", "") for element in feature.findall("plugin")]
    assert_exact(feature_plugins, "packaged feature plugin IDs")
    feature_identities = {(element.attrib.get("id", ""), element.attrib.get("version", ""))
                          for element in feature.findall("plugin")}
    if feature_identities != expected_identities or len(feature.findall("plugin")) != 4:
        fail(f"packaged feature plugin identities differ: {sorted(feature_identities ^ expected_identities)}")

    artifacts = compressed_xml(repository, "artifacts.jar", "artifacts.xml")
    artifact_elements = [artifact
                        for artifact in artifacts.findall("./artifacts/artifact")
                        if artifact.attrib.get("classifier") == "osgi.bundle"]
    artifact_bundles = [artifact.attrib.get("id", "") for artifact in artifact_elements]
    assert_exact(artifact_bundles, "osgi.bundle artifacts")
    artifact_identities = [(artifact.attrib.get("id", ""), artifact.attrib.get("version", ""))
                           for artifact in artifact_elements]
    if len(artifact_identities) != len(set(artifact_identities)) or set(artifact_identities) != expected_identities:
        fail(f"unexpected osgi.bundle artifact identities: {artifact_identities}")

    content = compressed_xml(repository, "content.jar", "content.xml")
    provided_bundles = []
    unit_identities = []
    for unit in content.findall("./units/unit"):
        provisions = unit.findall("./provides/provided")
        bundles = [item for item in provisions if item.attrib.get("namespace") == "osgi.bundle"]
        if bundles:
            identity = (unit.attrib.get("id", ""), unit.attrib.get("version", ""))
            provided_bundles.append(identity[0])
            unit_identities.append(identity)
            if len(bundles) != 1 or (bundles[0].attrib.get("name"), bundles[0].attrib.get("version")) != identity:
                fail(f"invalid osgi.bundle capability for IU {identity}")
            iu = [item for item in provisions if item.attrib.get("namespace") == "org.eclipse.equinox.p2.iu"]
            if len(iu) != 1 or (iu[0].attrib.get("name"), iu[0].attrib.get("version")) != identity:
                fail(f"invalid p2 IU identity capability for IU {identity}")
    assert_exact(provided_bundles, "osgi.bundle IUs")
    if len(unit_identities) != len(set(unit_identities)) or set(unit_identities) != expected_identities:
        fail(f"unexpected osgi.bundle IU identities: {unit_identities}")
    print("production p2 plugin, feature, artifact, and IU sets are exact")


if __name__ == "__main__":
    main()
