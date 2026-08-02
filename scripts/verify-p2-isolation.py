#!/usr/bin/env python3
"""Verify the generated production p2 repository is a closed five-artifact set."""

from __future__ import annotations

import hashlib
import io
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
TEST_MARKERS = (".tests", "junit", "surefire", "opentest4j", "apiguardian", "vintage", "testng")
REPOSITORY_NAME = "io.github.bakhtiiartashbolotov.dbeaver.monaco.repository"
JRE_CAPABILITY_DIGEST = "e652aa1bceb4e97f3b0cf6b27afe490bcaf59fc965d6afd83249aa8ebac4057c"


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


def archive_has_test_payload(archive: zipfile.ZipFile, label: str, depth: int = 0) -> None:
    if depth > 2 or len(archive.infolist()) > 10000:
        fail(f"archive inspection bound exceeded: {label}")
    for entry in archive.infolist():
        normalized = entry.filename.replace("\\", "/").lower()
        if any(marker in normalized for marker in TEST_MARKERS):
            fail(f"test/JUnit marker in production bundle payload or manifest: {label}")
        if not entry.is_dir() and normalized.endswith((".jar", ".zip")):
            data = archive.read(entry)
            if len(data) > 64 * 1024 * 1024:
                fail(f"nested archive inspection bound exceeded: {label}:{entry.filename}")
            try:
                with zipfile.ZipFile(io.BytesIO(data)) as nested:
                    archive_has_test_payload(nested, f"{label}:{entry.filename}", depth + 1)
            except zipfile.BadZipFile as error:
                fail(f"unreadable nested archive: {label}:{entry.filename}: {error}")
            fail(f"nested archive is forbidden in production scaffold: {label}:{entry.filename}")


def manifest_identity(bundle: Path) -> tuple[str, str]:
    try:
        with zipfile.ZipFile(bundle) as archive:
            archive_has_test_payload(archive, bundle.name)
            text = archive.read("META-INF/MANIFEST.MF").decode("utf-8")
            payload_names = archive.namelist()
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
    if any(marker in value.lower() for value in [*payload_names, *logical] for marker in TEST_MARKERS):
        fail(f"test/JUnit marker in production bundle payload or manifest: {bundle.name}")
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


def require_size(container: ET.Element, children: list[ET.Element], label: str) -> None:
    if container.attrib != {"size": str(len(children))}:
        fail(f"incorrect {label} size attribute")


def require_attributes(element: ET.Element, expected: set[str], label: str) -> None:
    if set(element.attrib) != expected:
        fail(f"unexpected {label} attributes: {sorted(set(element.attrib) ^ expected)}")


def validate_properties_container(element: ET.Element, label: str) -> dict[str, str]:
    if element.tag != "properties":
        fail(f"missing {label} properties")
    items = list(element)
    require_size(element, items, f"{label} properties")
    if any(item.tag != "property" or set(item.attrib) != {"name", "value"} or list(item)
           for item in items):
        fail(f"invalid {label} property structure")
    values = [(item.attrib["name"], item.attrib["value"]) for item in items]
    if len(values) != len(dict(values)):
        fail(f"duplicate {label} properties")
    return dict(values)


def validate_sized_children(element: ET.Element, child_tags: set[str], label: str) -> list[ET.Element]:
    children = list(element)
    if any(child.tag not in child_tags for child in children):
        fail(f"unexpected {label} child")
    require_size(element, children, label)
    return children


def validate_provides(unit: ET.Element, expected: set[tuple[str, str, str]], label: str) -> None:
    containers = unit.findall("provides")
    if len(containers) != 1:
        fail(f"missing {label} provides")
    items = validate_sized_children(containers[0], {"provided"}, f"{label} provides")
    if any(set(item.attrib) != {"namespace", "name", "version"} for item in items):
        fail(f"invalid {label} provided capability structure")
    for item in items:
        children = list(item)
        if item.attrib["namespace"] == "osgi.identity":
            if len(children) != 1 or validate_properties_container(children[0], f"{label} identity") != {
                    "type": "osgi.bundle"}:
                fail(f"invalid {label} identity properties")
        elif children:
            fail(f"unexpected nested {label} capability structure")
    actual = {(item.attrib["namespace"], item.attrib["name"], item.attrib["version"]) for item in items}
    if len(actual) != len(items) or actual != expected:
        fail(f"unexpected {label} capabilities")


def validate_required_properties(item: ET.Element, identifier: str) -> None:
    if item.attrib != {"namespace": "osgi.ee", "match": "(&(osgi.ee=JavaSE)(version=21))"}:
        fail(f"invalid JavaSE-21 requiredProperties: {identifier}")
    children = list(item)
    if (len(children) != 1 or children[0].tag != "description" or children[0].attrib
            or list(children[0]) or (children[0].text or "").strip() != identifier):
        fail(f"invalid requiredProperties description: {identifier}")


def validate_bundle_touchpoint(unit: ET.Element, identifier: str, version: str) -> None:
    touchpoint = unit.find("touchpoint")
    if touchpoint is None or touchpoint.attrib != {"id": "org.eclipse.equinox.p2.osgi", "version": "1.0.0"} \
            or list(touchpoint):
        fail(f"invalid bundle touchpoint: {identifier}")
    data = unit.find("touchpointData")
    if data is None:
        fail(f"missing bundle touchpoint data: {identifier}")
    instructions = validate_sized_children(data, {"instructions"}, f"{identifier} touchpointData")
    if len(instructions) != 1:
        fail(f"invalid bundle touchpointData: {identifier}")
    entries = validate_sized_children(instructions[0], {"instruction"}, f"{identifier} instructions")
    if len(entries) != 1 or entries[0].attrib != {"key": "manifest"} or list(entries[0]):
        fail(f"invalid bundle manifest instruction: {identifier}")
    manifest = (entries[0].text or "").strip()
    expected = f"Bundle-SymbolicName: {identifier};singleton:=true\nBundle-Version: {version}"
    if manifest != expected:
        fail(f"invalid bundle manifest instruction content: {identifier}")


def validate_legal_metadata(unit: ET.Element, label: str) -> None:
    licenses = unit.find("licenses")
    if licenses is None:
        fail(f"missing {label} license")
    entries = validate_sized_children(licenses, {"license"}, f"{label} licenses")
    apache = "https://www.apache.org/licenses/LICENSE-2.0"
    if (len(entries) != 1 or entries[0].attrib != {"uri": apache, "url": apache}
            or list(entries[0]) or (entries[0].text or "").strip() != "Apache License 2.0"):
        fail(f"invalid {label} license")
    copyright_element = unit.find("copyright")
    if (copyright_element is None or copyright_element.attrib or list(copyright_element)
            or (copyright_element.text or "").strip() != "Copyright 2026."):
        fail(f"invalid {label} copyright")


def exact_elements(parent: ET.Element, tags: list[str], label: str) -> None:
    if [child.tag for child in parent] != tags:
        fail(f"unexpected {label} root children")


def exact_artifact_reference(unit: ET.Element, expected: tuple[str, str, str] | None, label: str) -> None:
    containers = unit.findall("artifacts")
    if expected is None:
        if containers:
            fail(f"unexpected artifact reference on {label}")
        return
    if len(containers) != 1:
        fail(f"missing artifact reference on {label}")
    refs = validate_sized_children(containers[0], {"artifact"}, f"{label} artifacts")
    actual = [(item.attrib.get("classifier"), item.attrib.get("id"), item.attrib.get("version")) for item in refs]
    if (actual != [expected] or any(set(item.attrib) != {"classifier", "id", "version"}
                                    or list(item) for item in refs)):
        fail(f"incorrect artifact reference on {label}")


def exact_capability(unit: ET.Element, expected: tuple[str, str, str], label: str) -> None:
    matches = [item for item in unit.findall("./provides/provided")
               if item.attrib.get("namespace") == expected[0]]
    if len(matches) != 1 or tuple(matches[0].attrib.get(key, "")
            for key in ("namespace", "name", "version")) != expected or len(matches[0].attrib) != 3:
        fail(f"incorrect {label} capability")


def exact_requirements(unit: ET.Element, expected: set[tuple[tuple[str, str], ...]], label: str,
                       filters: dict[str, str] | None = None, java_identifier: str | None = None) -> None:
    containers = unit.findall("requires")
    if not expected and java_identifier is None:
        if containers:
            fail(f"unexpected {label} requirements container")
        return
    if len(containers) != 1:
        fail(f"missing {label} requirements container")
    children = list(containers[0])
    require_size(containers[0], children, f"{label} requires")
    requirements = [item for item in children if item.tag == "required"]
    required_properties = [item for item in children if item.tag == "requiredProperties"]
    if len(requirements) + len(required_properties) != len(children):
        fail(f"unexpected {label} requirement child")
    if java_identifier is None and required_properties:
        fail(f"unexpected {label} requiredProperties")
    if java_identifier is not None:
        if len(required_properties) != 1:
            fail(f"missing JavaSE-21 requiredProperties: {java_identifier}")
        validate_required_properties(required_properties[0], java_identifier)
    actual = {tuple(sorted(item.attrib.items())) for item in requirements}
    structure_ok = True
    for item in requirements:
        children = list(item)
        expected_filter = (filters or {}).get(item.attrib.get("name", ""))
        expected_attributes = {"namespace", "name", "range"}
        if item.attrib.get("optional") == "true":
            expected_attributes.add("optional")
        if set(item.attrib) != expected_attributes:
            structure_ok = False
        if expected_filter is not None:
            structure_ok = (structure_ok and len(children) == 1 and children[0].tag == "filter"
                            and not children[0].attrib
                            and (children[0].text or "").strip() == expected_filter
                            and not list(children[0]))
        elif children:
            structure_ok = False
    if len(requirements) != len(expected) or actual != expected or not structure_ok:
        fail(f"unexpected {label} requirements: actual={actual} expected={expected}")


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
            or set(artifacts.attrib) != {"name", "type", "version"}
            or artifacts.attrib.get("name") != REPOSITORY_NAME
            or artifacts.attrib.get("type") != "org.eclipse.equinox.p2.artifact.repository.simpleRepository"
            or artifacts.attrib.get("version") != "1"
            or len(artifacts.findall("artifacts")) != 1):
        fail("invalid artifacts metadata root or container structure")
    if (content.tag != "repository"
            or set(content.attrib) != {"name", "type", "version"}
            or content.attrib.get("name") != REPOSITORY_NAME
            or content.attrib.get("type") != "org.eclipse.equinox.internal.p2.metadata.repository.LocalMetadataRepository"
            or content.attrib.get("version") != "1"
            or len(content.findall("units")) != 1):
        fail("invalid content metadata root or container structure")
    exact_elements(artifacts, ["properties", "mappings", "artifacts"], "artifacts metadata")
    exact_elements(content, ["properties", "units"], "content metadata")
    artifact_properties = artifacts.find("properties")
    mappings = artifacts.find("mappings")
    artifact_container = artifacts.find("artifacts")
    content_properties = content.find("properties")
    unit_container = content.find("units")
    assert artifact_properties is not None and mappings is not None and artifact_container is not None
    assert content_properties is not None and unit_container is not None
    artifact_repository_properties = validate_properties_container(artifact_properties, "repository artifact")
    content_repository_properties = validate_properties_container(content_properties, "repository content")
    for label, values in (("artifact", artifact_repository_properties),
                          ("content", content_repository_properties)):
        if (set(values) != {"p2.timestamp", "p2.compressed"}
                or not values["p2.timestamp"].isdigit() or values["p2.compressed"] != "true"):
            fail(f"invalid repository {label} property values")
    mapping_rules = mappings.findall("rule")
    require_size(mappings, mapping_rules, "mappings")
    expected_mappings = [
        {"filter": "(& (classifier=osgi.bundle))", "output": "${repoUrl}/plugins/${id}_${version}.jar"},
        {"filter": "(& (classifier=binary))", "output": "${repoUrl}/binary/${id}_${version}"},
        {"filter": "(& (classifier=org.eclipse.update.feature))",
         "output": "${repoUrl}/features/${id}_${version}.jar"},
    ]
    if [item.attrib for item in mapping_rules] != expected_mappings or any(list(item) for item in mapping_rules):
        fail("unexpected artifact mapping rules")

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
            feature_members = archive.namelist()
            feature_payloads = {name: archive.read(name) for name in feature_members if not name.endswith("/")}
            feature_xml = ET.fromstring(feature_payloads["feature.xml"])
    except (KeyError, ET.ParseError, zipfile.BadZipFile) as error:
        fail(f"invalid packaged feature: {error}")
    textual_feature = [name for name in feature_members]
    textual_feature.extend(data.decode("utf-8", errors="replace") for data in feature_payloads.values())
    if any(marker in value.lower() for value in textual_feature for marker in TEST_MARKERS):
        fail("test/JUnit marker in packaged feature payload or metadata")
    if feature_members != ["META-INF/", "META-INF/MANIFEST.MF", "feature.xml"]:
        fail(f"unexpected packaged feature members: {feature_members}")
    feature_manifest_lines = []
    for line in feature_payloads["META-INF/MANIFEST.MF"].decode("utf-8").replace("\r\n", "\n").splitlines():
        if line.startswith(" ") and feature_manifest_lines:
            feature_manifest_lines[-1] += line[1:]
        elif line:
            feature_manifest_lines.append(line)
    feature_manifest = dict(line.split(":", 1) for line in feature_manifest_lines if ":" in line)
    feature_manifest = {name: value.strip() for name, value in feature_manifest.items()}
    if feature_manifest != {"Manifest-Version": "1.0", "Created-By": "Maven Archiver 3.6.6",
                            "Build-Jdk-Spec": "21", "Java-Version": "21"}:
        fail(f"invalid packaged feature Java/build manifest: {feature_manifest}")
    allowed_feature_children = ["description", "copyright", "license", "plugin", "plugin", "plugin", "plugin"]
    if feature_xml.tag != "feature" or feature_xml.attrib.get("id") != FEATURE:
        fail("invalid packaged feature root or ID")
    if [child.tag for child in feature_xml] != allowed_feature_children:
        fail("packaged feature contains include/import/require or unknown structure")
    require_attributes(feature_xml, {"id", "label", "version", "provider-name"}, "packaged feature")
    for child in feature_xml[:3]:
        expected_attributes = {"url"} if child.tag == "license" else set()
        if set(child.attrib) != expected_attributes or list(child):
            fail(f"invalid packaged feature {child.tag} structure")
    plugins = feature_xml.findall("plugin")
    feature_identities = {(item.attrib.get("id", ""), item.attrib.get("version", "")) for item in plugins}
    if (len(plugins) != 4 or feature_identities != identities
            or any(set(item.attrib) != {"id", "version"} or list(item) for item in plugins)):
        fail("packaged feature plugin identities or structure differ")
    feature_version = feature_xml.attrib.get("version", "")
    if not feature_version:
        fail("packaged feature version is empty")

    artifact_elements = validate_sized_children(artifact_container, {"artifact"}, "artifacts")
    artifact_roles = [(item.attrib.get("classifier", ""), item.attrib.get("id", ""), item.attrib.get("version", ""))
                      for item in artifact_elements]
    expected_artifact_roles = {("osgi.bundle", name, version) for name, version in identities}
    expected_artifact_roles.add(("org.eclipse.update.feature", FEATURE, feature_version))
    if len(artifact_roles) != 5 or set(artifact_roles) != expected_artifact_roles:
        fail(f"unexpected artifact universe: {artifact_roles}")
    if any(any(marker in " ".join(role).lower() for marker in TEST_MARKERS) for role in artifact_roles):
        fail("test-only artifact metadata")
    for element, (classifier, identifier, version) in zip(artifact_elements, artifact_roles):
        if set(element.attrib) != {"classifier", "id", "version"} or [child.tag for child in element] != ["properties"]:
            fail(f"invalid artifact element structure: {identifier}")
        jar = (repository / "plugins" / f"{identifier}_{version}.jar" if classifier == "osgi.bundle"
               else repository / "features" / f"{identifier}_{version}.jar")
        if not jar.is_file():
            fail(f"missing declared artifact JAR: {jar}")
        data = jar.read_bytes()
        props = validate_properties_container(element.find("properties"), f"artifact {identifier}")
        expected_property_names = {
            "artifact.size", "download.size", "maven-groupId", "maven-artifactId",
            "maven-version", "maven-type", "download.checksum.sha-256", "download.checksum.sha-512",
        }
        if classifier == "org.eclipse.update.feature":
            expected_property_names.add("download.contentType")
        if set(props) != expected_property_names:
            fail(f"unexpected artifact properties: {identifier}")
        expected_type = "eclipse-plugin" if classifier == "osgi.bundle" else "eclipse-feature"
        if (props["maven-groupId"] != "io.github.bakhtiiartashbolotov"
                or props["maven-artifactId"] != identifier
                or props["maven-version"] != "0.1.0-SNAPSHOT"
                or props["maven-type"] != expected_type
                or (classifier == "org.eclipse.update.feature"
                    and props["download.contentType"] != "application/zip")):
            fail(f"invalid artifact Maven/property values: {identifier}")
        if props.get("artifact.size") != str(len(data)) or props.get("download.size") != str(len(data)):
            fail(f"incorrect declared artifact size: {identifier}")
        if props.get("download.checksum.sha-256") != hashlib.sha256(data).hexdigest():
            fail(f"incorrect SHA-256: {identifier}")
        if props.get("download.checksum.sha-512") != hashlib.sha512(data).hexdigest():
            fail(f"incorrect SHA-512: {identifier}")

    units = validate_sized_children(unit_container, {"unit"}, "units")
    unit_map = {unit.attrib.get("id", ""): unit for unit in units}
    if len(units) != 8 or len(unit_map) != 8:
        fail(f"expected exactly eight unique IUs, found {len(units)}")
    for unit in units:
        if any(marker in ET.tostring(unit, encoding="unicode").lower() for marker in TEST_MARKERS):
            fail(f"test-only IU metadata: {unit.attrib.get('id', '')}")
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
    try:
        category_source = ET.parse("repository/category.xml").getroot()
    except (OSError, ET.ParseError) as error:
        fail(f"unreadable canonical category.xml: {error}")
    category_defs = category_source.findall("category-def")
    source_features = category_source.findall("feature")
    if (category_source.tag != "site" or category_source.attrib or len(category_defs) != 1
            or len(source_features) != 1 or category_defs[0].attrib != {
                "name": "dbeaver-monaco", "label": "DBeaver Monaco Editor"}
            or source_features[0].attrib != {"id": FEATURE, "version": "0.0.0"}
            or len(source_features[0]) != 1 or source_features[0][0].tag != "category"
            or source_features[0][0].attrib != {"name": "dbeaver-monaco"}):
        fail("invalid canonical category.xml relationship")
    if set(unit_map) != expected_ids | {category.attrib["id"]}:
        fail(f"unexpected IU universe: {sorted(set(unit_map) ^ (expected_ids | {category.attrib['id']}))}")
    if unit_map["a.jre.javase"].attrib.get("version") != "21.0.0":
        fail("unexpected Java execution-environment IU")

    for identifier, version in identities:
        unit = unit_map[identifier]
        require_attributes(unit, {"id", "version", "generation"}, f"bundle IU {identifier}")
        if unit.attrib["id"] != identifier or unit.attrib["generation"] != "2":
            fail(f"invalid bundle IU identity attributes: {identifier}")
        if [child.tag for child in unit] != ["update", "properties", "provides", "requires", "artifacts",
                                             "touchpoint", "touchpointData"]:
            fail(f"unexpected bundle IU structure: {identifier}")
        if unit.attrib.get("version") != version:
            fail(f"bundle IU version mismatch: {identifier}")
        update = unit.find("update")
        if update is None or update.attrib != {
                "id": identifier, "range": f"[0.0.0,{version})", "severity": "0"} or list(update):
            fail(f"invalid bundle update metadata: {identifier}")
        bundle_properties = validate_properties_container(unit.find("properties"), f"bundle IU {identifier}")
        expected_bundle_property_names = {
            "org.eclipse.equinox.p2.name", "maven-groupId", "maven-artifactId", "maven-version", "maven-type"}
        if set(bundle_properties) != expected_bundle_property_names:
            fail(f"unexpected bundle IU properties: {identifier}")
        if (bundle_properties["maven-artifactId"] != identifier
                or bundle_properties["maven-groupId"] != "io.github.bakhtiiartashbolotov"
                or bundle_properties["maven-version"] != "0.1.0-SNAPSHOT"
                or bundle_properties["maven-type"] != "eclipse-plugin"):
            fail(f"invalid bundle IU Maven properties: {identifier}")
        provisions = unit.findall("./provides/provided")
        bundle_caps = [item for item in provisions if item.attrib.get("namespace") == "osgi.bundle"]
        identity_caps = [item for item in provisions if item.attrib.get("namespace") == "org.eclipse.equinox.p2.iu"]
        if len(bundle_caps) != 1 or len(identity_caps) != 1:
            fail(f"invalid bundle capability cardinality: {identifier}")
        for capability in bundle_caps + identity_caps:
            if (capability.attrib.get("name"), capability.attrib.get("version")) != (identifier, version):
                fail(f"invalid bundle capability identity: {identifier}")
        validate_provides(unit, {
            ("org.eclipse.equinox.p2.iu", identifier, version),
            ("osgi.bundle", identifier, version),
            ("osgi.identity", identifier, version),
            ("org.eclipse.equinox.p2.eclipse.type", "bundle", "1.0.0"),
        }, f"bundle IU {identifier}")
        exact_artifact_reference(unit, ("osgi.bundle", identifier, version), identifier)
        exact_capability(unit, ("osgi.identity", identifier, version), f"{identifier} identity")
        exact_capability(unit, ("org.eclipse.equinox.p2.eclipse.type", "bundle", "1.0.0"),
                         f"{identifier} type")
        source_edge = tuple(sorted({
            "namespace": "org.eclipse.equinox.p2.iu",
            "name": f"{identifier}.source",
            "range": exact_range(version),
            "optional": "true",
        }.items()))
        expected_bundle_edges = {source_edge}
        if identifier.endswith(".ui"):
            expected_bundle_edges.add(tuple(sorted({
                "namespace": "osgi.bundle",
                "name": "org.jkiss.dbeaver.ui.editors.sql",
                "range": "[1.0.180,2.0.0)",
            }.items())))
        exact_requirements(unit, expected_bundle_edges, f"{identifier} bundle",
                           {f"{identifier}.source": "(org.eclipse.update.install.sources=true)"}, identifier)
        validate_bundle_touchpoint(unit, identifier, version)

    feature_jar = unit_map[feature_jar_id]
    require_attributes(feature_jar, {"id", "version"}, "feature.jar IU")
    if feature_jar.attrib["id"] != feature_jar_id:
        fail("invalid feature.jar IU identity")
    if [child.tag for child in feature_jar] != ["properties", "provides", "filter", "artifacts", "touchpoint",
                                                   "touchpointData", "licenses", "copyright"]:
        fail("unexpected feature.jar IU structure")
    if feature_jar.attrib.get("version") != feature_version:
        fail("feature.jar IU version mismatch")
    exact_artifact_reference(feature_jar, ("org.eclipse.update.feature", FEATURE, feature_version), "feature.jar")
    exact_capability(feature_jar, ("org.eclipse.equinox.p2.iu", feature_jar_id, feature_version),
                     "feature.jar self")
    exact_capability(feature_jar, ("org.eclipse.equinox.p2.eclipse.type", "feature", "1.0.0"),
                     "feature.jar type")
    exact_capability(feature_jar, ("org.eclipse.update.feature", FEATURE, feature_version),
                     "feature.jar update-feature")
    validate_provides(feature_jar, {
        ("org.eclipse.equinox.p2.iu", feature_jar_id, feature_version),
        ("org.eclipse.equinox.p2.eclipse.type", "feature", "1.0.0"),
        ("org.eclipse.update.feature", FEATURE, feature_version),
    }, "feature.jar")
    feature_jar_properties = validate_properties_container(feature_jar.find("properties"), "feature.jar")
    if set(feature_jar_properties) != {
            "org.eclipse.equinox.p2.name", "org.eclipse.equinox.p2.description",
            "org.eclipse.equinox.p2.provider", "maven-groupId", "maven-artifactId", "maven-version",
            "maven-type"}:
        fail("unexpected feature.jar properties")
    if (feature_jar_properties["org.eclipse.equinox.p2.name"] != "DBeaver Monaco Editor"
            or feature_jar_properties["org.eclipse.equinox.p2.description"]
            != "Monaco presentation extension scaffold."
            or feature_jar_properties["org.eclipse.equinox.p2.provider"] != "bakhtiiartashbolotov"
            or feature_jar_properties["maven-groupId"] != "io.github.bakhtiiartashbolotov"
            or feature_jar_properties["maven-artifactId"] != FEATURE
            or feature_jar_properties["maven-version"] != "0.1.0-SNAPSHOT"
            or feature_jar_properties["maven-type"] != "eclipse-feature"):
        fail("invalid feature.jar property values")
    feature_filter = feature_jar.find("filter")
    if (feature_filter is None or feature_filter.attrib or list(feature_filter)
            or (feature_filter.text or "").strip() != "(org.eclipse.update.install.features=true)"):
        fail("invalid feature.jar filter")
    feature_touchpoint = feature_jar.find("touchpoint")
    if (feature_touchpoint is None
            or feature_touchpoint.attrib != {"id": "org.eclipse.equinox.p2.osgi", "version": "1.0.0"}
            or list(feature_touchpoint)):
        fail("invalid feature.jar touchpoint")
    feature_data = feature_jar.find("touchpointData")
    if feature_data is None:
        fail("missing feature.jar touchpoint data")
    instruction_groups = validate_sized_children(feature_data, {"instructions"}, "feature.jar touchpointData")
    if len(instruction_groups) != 1:
        fail("invalid feature.jar touchpointData")
    instructions = validate_sized_children(instruction_groups[0], {"instruction"}, "feature.jar instructions")
    if (len(instructions) != 1 or instructions[0].attrib != {"key": "zipped"}
            or list(instructions[0]) or (instructions[0].text or "").strip() != "true"):
        fail("invalid feature.jar touchpoint instruction")
    validate_legal_metadata(feature_jar, "feature.jar")
    exact_requirements(feature_jar, set(), "feature.jar")
    group = unit_map[feature_group_id]
    require_attributes(group, {"id", "version", "singleton"}, "feature.group IU")
    if group.attrib["id"] != feature_group_id or group.attrib["singleton"] != "false":
        fail("invalid feature.group IU identity attributes")
    if [child.tag for child in group] != ["update", "properties", "provides", "requires", "licenses", "copyright"]:
        fail("unexpected feature.group IU structure")
    if group.attrib.get("version") != feature_version:
        fail("feature.group IU version mismatch")
    exact_artifact_reference(group, None, "feature.group")
    exact_capability(group, ("org.eclipse.equinox.p2.iu", feature_group_id, feature_version),
                     "feature.group self")
    validate_provides(group, {("org.eclipse.equinox.p2.iu", feature_group_id, feature_version)}, "feature.group")
    group_properties = validate_properties_container(group.find("properties"), "feature.group")
    if group_properties.get("org.eclipse.equinox.p2.type.group") != "true" or set(group_properties) != {
            "org.eclipse.equinox.p2.name", "org.eclipse.equinox.p2.description",
            "org.eclipse.equinox.p2.provider", "org.eclipse.equinox.p2.type.group", "maven-groupId",
            "maven-artifactId", "maven-version", "maven-type"}:
        fail("missing or invalid feature.group role property")
    if (group_properties["org.eclipse.equinox.p2.name"] != "DBeaver Monaco Editor"
            or group_properties["org.eclipse.equinox.p2.description"]
            != "Monaco presentation extension scaffold."
            or group_properties["org.eclipse.equinox.p2.provider"] != "bakhtiiartashbolotov"
            or group_properties["maven-groupId"] != "io.github.bakhtiiartashbolotov"
            or group_properties["maven-artifactId"] != FEATURE
            or group_properties["maven-version"] != "0.1.0-SNAPSHOT"
            or group_properties["maven-type"] != "eclipse-feature"):
        fail("invalid feature.group property values")
    group_update = group.find("update")
    if group_update is None or group_update.attrib != {
            "id": feature_group_id, "range": f"[0.0.0,{feature_version})", "severity": "0"} \
            or list(group_update):
        fail("invalid feature.group update metadata")
    validate_legal_metadata(group, "feature.group")
    expected_edges = {tuple(sorted({"namespace": "org.eclipse.equinox.p2.iu", "name": name,
                                    "range": exact_range(version)}.items())) for name, version in identities}
    expected_edges.add(tuple(sorted({"namespace": "org.eclipse.equinox.p2.iu", "name": feature_jar_id,
                                     "range": exact_range(feature_version)}.items())))
    exact_requirements(group, expected_edges, "feature.group",
                       {feature_jar_id: "(org.eclipse.update.install.features=true)"})

    category_id = category.attrib.get("id", "")
    category_version = category.attrib.get("version", "")
    if not category_id or not category_version:
        fail("invalid category identity")
    exact_artifact_reference(category, None, "category")
    require_attributes(category, {"id", "version"}, "category IU")
    if category.attrib != {"id": category_id, "version": category_version}:
        fail("invalid category IU identity attributes")
    if [child.tag for child in category] != ["properties", "provides", "requires"]:
        fail("unexpected category IU structure")
    category_properties = validate_properties_container(category.find("properties"), "category")
    if category_properties.get("org.eclipse.equinox.p2.type.category") != "true" or set(category_properties) != {
            "org.eclipse.equinox.p2.name", "org.eclipse.equinox.p2.type.category"}:
        fail("invalid category properties")
    if (category_properties["org.eclipse.equinox.p2.name"] != category_defs[0].attrib["label"]
            or not category_id.endswith(f".{category_defs[0].attrib['name']}")):
        fail("invalid generated category relationship")
    validate_provides(category, {("org.eclipse.equinox.p2.iu", category_id, category_version)}, "category")
    exact_capability(category, ("org.eclipse.equinox.p2.iu", category_id, category_version), "category self")
    category_edge = {tuple(sorted({"namespace": "org.eclipse.equinox.p2.iu", "name": feature_group_id,
                                   "range": exact_range(feature_version)}.items()))}
    exact_requirements(category, category_edge, "category")

    jre = unit_map["a.jre.javase"]
    require_attributes(jre, {"id", "version", "singleton"}, "Java IU")
    if jre.attrib != {"id": "a.jre.javase", "version": "21.0.0", "singleton": "false"}:
        fail("invalid Java IU identity attributes")
    if [child.tag for child in jre] != ["provides", "touchpoint"]:
        fail("unexpected Java IU structure")
    jre_provides = jre.find("provides")
    if jre_provides is None:
        fail("missing Java capabilities")
    jre_caps = validate_sized_children(jre_provides, {"provided"}, "Java provides")
    if len(jre_caps) != 260 or any(set(item.attrib) != {"namespace", "name", "version"} or list(item)
                                   for item in jre_caps):
        fail("invalid Java capability universe")
    normalized_jre = sorted("\0".join((item.attrib["namespace"], item.attrib["name"], item.attrib["version"]))
                            for item in jre_caps)
    if hashlib.sha256("\n".join(normalized_jre).encode()).hexdigest() != JRE_CAPABILITY_DIGEST:
        fail("invalid Java capability universe digest")
    jre_touchpoint = jre.find("touchpoint")
    if jre_touchpoint is None or jre_touchpoint.attrib != {
            "id": "org.eclipse.equinox.p2.native", "version": "1.0.0"} or list(jre_touchpoint):
        fail("invalid Java touchpoint")
    exact_artifact_reference(jre, None, "a.jre.javase")
    exact_capability(jre, ("org.eclipse.equinox.p2.iu", "a.jre.javase", "21.0.0"), "Java self")
    exact_requirements(jre, set(), "Java execution environment")
    print("production p2 repository topology, representations, artifacts, hashes, and IUs are exact")


if __name__ == "__main__":
    main()
