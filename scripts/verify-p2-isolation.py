#!/usr/bin/env python3
"""Verify the generated production p2 repository is a closed five-artifact set."""

from __future__ import annotations

import hashlib
import lzma
from pathlib import Path
import stat
import sys
import xml.etree.ElementTree as ET
import zipfile

BUNDLES = {
    "io.github.bakhtiiartashbolotov.dbeaver.monaco.bridge",
    "io.github.bakhtiiartashbolotov.dbeaver.monaco.core",
    "io.github.bakhtiiartashbolotov.dbeaver.monaco.ui",
    "io.github.bakhtiiartashbolotov.dbeaver.monaco.web",
}
FEATURE = "io.github.bakhtiiartashbolotov.dbeaver.monaco.feature"
TOP_LEVEL = {"artifacts.jar", "artifacts.xml.xz", "content.jar", "content.xml.xz", "p2.index", "features", "plugins"}
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


def metadata_bytes(repository: Path, base: str) -> bytes:
    xz_path = repository / f"{base}.xml.xz"
    jar_path = repository / f"{base}.jar"
    if not xz_path.is_file() or xz_path.is_symlink() or not jar_path.is_file() or jar_path.is_symlink():
        fail(f"missing authoritative {base} metadata representations")
    try:
        xz_data = lzma.decompress(xz_path.read_bytes())
        with zipfile.ZipFile(jar_path) as archive:
            if archive.namelist() != [f"{base}.xml"]:
                fail(f"unexpected {base}.jar members: {archive.namelist()}")
            jar_data = archive.read(f"{base}.xml")
    except (lzma.LZMAError, zipfile.BadZipFile, KeyError) as error:
        fail(f"unreadable {base} metadata: {error}")
    if xz_data != jar_data:
        fail(f"{base} XZ/JAR metadata representations diverge")
    return xz_data


def properties(element: ET.Element) -> dict[str, str]:
    values = [(item.attrib.get("name", ""), item.attrib.get("value", ""))
              for item in element.findall("./properties/property")]
    if len(values) != len(dict(values)):
        fail(f"duplicate properties on {element.tag}")
    return dict(values)


def exact_range(version: str) -> str:
    return f"[{version},{version}]"


def main() -> None:
    if len(sys.argv) != 2:
        fail(f"usage: {sys.argv[0]} <repository-directory>")
    repository = Path(sys.argv[1])
    if not repository.is_dir() or repository.is_symlink():
        fail(f"missing real repository directory: {repository}")
    entries = {entry.name for entry in repository.iterdir()}
    if entries != TOP_LEVEL:
        fail(f"unexpected repository top-level entries: {sorted(entries ^ TOP_LEVEL)}")
    for name in TOP_LEVEL:
        entry = repository / name
        expected_directory = name in {"features", "plugins"}
        mode = entry.lstat().st_mode
        if entry.is_symlink() or (expected_directory and not stat.S_ISDIR(mode)) \
                or (not expected_directory and not stat.S_ISREG(mode)):
            fail(f"unexpected repository entry type: {name}")

    index_lines = [line for line in (repository / "p2.index").read_text(encoding="utf-8").splitlines()
                   if line and not line.startswith("#")]
    expected_index = [
        r"artifact.repository.factory.order=artifacts.xml.xz,artifacts.xml,\!",
        r"metadata.repository.factory.order=content.xml.xz,content.xml,\!",
        "version=1",
    ]
    if index_lines != expected_index:
        fail(f"unexpected p2.index factory order: {index_lines}")

    artifacts = ET.fromstring(metadata_bytes(repository, "artifacts"))
    content = ET.fromstring(metadata_bytes(repository, "content"))
    if (artifacts.tag != "repository"
            or artifacts.attrib.get("type") != "org.eclipse.equinox.p2.artifact.repository.simpleRepository"
            or artifacts.attrib.get("version") != "1"
            or len(artifacts.findall("artifacts")) != 1):
        fail("invalid artifacts metadata root or container structure")
    if (content.tag != "repository"
            or content.attrib.get("type") != "org.eclipse.equinox.internal.p2.metadata.repository.LocalMetadataRepository"
            or content.attrib.get("version") != "1"
            or len(content.findall("units")) != 1):
        fail("invalid content metadata root or container structure")

    plugin_jars = closed_jars(repository / "plugins", "plugins")
    plugin_identities = [manifest_identity(bundle) for bundle in plugin_jars]
    if len(plugin_identities) != 4 or {item[0] for item in plugin_identities} != BUNDLES:
        fail(f"unexpected plugin identities: {plugin_identities}")
    if any(any(marker in name.lower() for marker in TEST_MARKERS) for name, _ in plugin_identities):
        fail("test-only production plugin")
    identities = set(plugin_identities)

    feature_jars = closed_jars(repository / "features", "features")
    if len(feature_jars) != 1:
        fail(f"expected one feature JAR, found {len(feature_jars)}")
    try:
        with zipfile.ZipFile(feature_jars[0]) as archive:
            feature_xml = ET.fromstring(archive.read("feature.xml"))
    except (KeyError, ET.ParseError, zipfile.BadZipFile) as error:
        fail(f"invalid packaged feature: {error}")
    allowed_feature_children = {"description", "copyright", "license", "plugin"}
    if feature_xml.tag != "feature" or feature_xml.attrib.get("id") != FEATURE:
        fail("invalid packaged feature root or ID")
    if any(child.tag not in allowed_feature_children for child in feature_xml):
        fail("packaged feature contains include/import/require or unknown structure")
    plugins = feature_xml.findall("plugin")
    feature_identities = {(item.attrib.get("id", ""), item.attrib.get("version", "")) for item in plugins}
    if len(plugins) != 4 or feature_identities != identities or any(list(item) for item in plugins):
        fail("packaged feature plugin identities or structure differ")
    feature_version = feature_xml.attrib.get("version", "")
    if not feature_version:
        fail("packaged feature version is empty")

    artifact_elements = artifacts.findall("./artifacts/artifact")
    artifact_roles = [(item.attrib.get("classifier", ""), item.attrib.get("id", ""), item.attrib.get("version", ""))
                      for item in artifact_elements]
    expected_artifact_roles = {("osgi.bundle", name, version) for name, version in identities}
    expected_artifact_roles.add(("org.eclipse.update.feature", FEATURE, feature_version))
    if len(artifact_roles) != 5 or set(artifact_roles) != expected_artifact_roles:
        fail(f"unexpected artifact universe: {artifact_roles}")
    if any(any(marker in " ".join(role).lower() for marker in TEST_MARKERS) for role in artifact_roles):
        fail("test-only artifact metadata")
    for element, (classifier, identifier, version) in zip(artifact_elements, artifact_roles):
        jar = (repository / "plugins" / f"{identifier}_{version}.jar" if classifier == "osgi.bundle"
               else repository / "features" / f"{identifier}_{version}.jar")
        if not jar.is_file():
            fail(f"missing declared artifact JAR: {jar}")
        data = jar.read_bytes()
        props = properties(element)
        if props.get("artifact.size") != str(len(data)) or props.get("download.size") != str(len(data)):
            fail(f"incorrect declared artifact size: {identifier}")
        if props.get("download.checksum.sha-256") != hashlib.sha256(data).hexdigest():
            fail(f"incorrect SHA-256: {identifier}")
        if props.get("download.checksum.sha-512") != hashlib.sha512(data).hexdigest():
            fail(f"incorrect SHA-512: {identifier}")

    units = content.findall("./units/unit")
    unit_map = {unit.attrib.get("id", ""): unit for unit in units}
    if len(units) != 8 or len(unit_map) != 8:
        fail(f"expected exactly eight unique IUs, found {len(units)}")
    for unit in units:
        metadata_names = [unit.attrib.get("id", "")]
        metadata_names.extend(item.attrib.get("name", "") for item in unit.findall("./provides/provided"))
        metadata_names.extend(item.attrib.get("name", "") for item in unit.findall("./requires/required"))
        metadata_names.extend(item.attrib.get("namespace", "") for item in unit.findall("./provides/provided"))
        metadata_names.extend(item.attrib.get("namespace", "") for item in unit.findall("./requires/required"))
        if any(marker in value.lower() for value in metadata_names for marker in TEST_MARKERS):
            fail(f"test-only IU metadata: {unit.attrib.get('id', '')}")
    bundle_ids = {name for name, _ in identities}
    feature_jar_id = f"{FEATURE}.feature.jar"
    feature_group_id = f"{FEATURE}.feature.group"
    categories = [unit for unit in units if properties(unit).get("org.eclipse.equinox.p2.type.category") == "true"]
    expected_ids = bundle_ids | {feature_jar_id, feature_group_id, "a.jre.javase"}
    if len(categories) != 1:
        fail(f"expected exactly one category IU, found {len(categories)}")
    category = categories[0]
    if set(unit_map) != expected_ids | {category.attrib["id"]}:
        fail(f"unexpected IU universe: {sorted(set(unit_map) ^ (expected_ids | {category.attrib['id']}))}")
    if unit_map["a.jre.javase"].attrib.get("version") != "21.0.0":
        fail("unexpected Java execution-environment IU")

    for identifier, version in identities:
        unit = unit_map[identifier]
        if unit.attrib.get("version") != version:
            fail(f"bundle IU version mismatch: {identifier}")
        provisions = unit.findall("./provides/provided")
        bundle_caps = [item for item in provisions if item.attrib.get("namespace") == "osgi.bundle"]
        identity_caps = [item for item in provisions if item.attrib.get("namespace") == "org.eclipse.equinox.p2.iu"]
        if len(bundle_caps) != 1 or len(identity_caps) != 1:
            fail(f"invalid bundle capability cardinality: {identifier}")
        for capability in bundle_caps + identity_caps:
            if (capability.attrib.get("name"), capability.attrib.get("version")) != (identifier, version):
                fail(f"invalid bundle capability identity: {identifier}")

    if unit_map[feature_jar_id].attrib.get("version") != feature_version:
        fail("feature.jar IU version mismatch")
    if unit_map[feature_jar_id].findall("./requires/required"):
        fail("feature.jar IU must have no direct requirements")
    group = unit_map[feature_group_id]
    if group.attrib.get("version") != feature_version:
        fail("feature.group IU version mismatch")
    requirements = group.findall("./requires/required")
    required_edges = {(item.attrib.get("namespace"), item.attrib.get("name"), item.attrib.get("range"))
                      for item in requirements}
    expected_edges = {("org.eclipse.equinox.p2.iu", name, exact_range(version)) for name, version in identities}
    expected_edges.add(("org.eclipse.equinox.p2.iu", feature_jar_id, exact_range(feature_version)))
    if len(requirements) != 5 or required_edges != expected_edges:
        fail(f"unexpected feature.group requirements: {required_edges ^ expected_edges}")

    category_requirements = category.findall("./requires/required")
    category_edge = ("org.eclipse.equinox.p2.iu", feature_group_id, exact_range(feature_version))
    if len(category_requirements) != 1 or tuple(category_requirements[0].attrib.get(name, "")
            for name in ("namespace", "name", "range")) != category_edge:
        fail("category does not require exactly the generated feature group")
    print("production p2 repository topology, representations, artifacts, hashes, and IUs are exact")


if __name__ == "__main__":
    main()
