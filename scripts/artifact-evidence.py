"""Deterministic Beacon SPDX evidence (standard library only)."""

import hashlib
import json
from pathlib import Path
import re
import sys
import tarfile


def metadata(path):
    values = {}
    for line in path.read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            if key in values:
                raise ValueError("duplicate metadata key")
            values[key] = value
    return values


def sbom(root, version, commit):
    lock = metadata(root / "base-bash-libs.lock")
    beacon = "SPDXRef-Package-Beacon"
    framework = "SPDXRef-Package-BaseBashLibs"
    files, relationships = [], [
        {"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES", "relatedSpdxElement": beacon},
        {"spdxElementId": beacon, "relationshipType": "DEPENDS_ON", "relatedSpdxElement": framework},
    ]
    hashes = {beacon: [], framework: []}
    for index, path in enumerate(sorted(p for p in root.rglob("*") if p.is_file()), 1):
        relative = path.relative_to(root).as_posix()
        content = path.read_bytes()
        sha1 = hashlib.sha1(content).hexdigest()
        owner = framework if relative.startswith("vendor/base-bash-libs/") else beacon
        hashes[owner].append(sha1)
        file_id = f"SPDXRef-File-{index}"
        files.append({
            "SPDXID": file_id, "fileName": "./" + relative,
            "checksums": [
                {"algorithm": "SHA1", "checksumValue": sha1},
                {"algorithm": "SHA256", "checksumValue": hashlib.sha256(content).hexdigest()},
            ],
            "licenseConcluded": "NOASSERTION",
        })
        relationships.append({"spdxElementId": owner, "relationshipType": "CONTAINS", "relatedSpdxElement": file_id})
    packages = []
    for identifier, name, release, source in (
        (beacon, "beacon", version, commit),
        (framework, "base-bash-libs", lock["version"], lock["commit"]),
    ):
        repo = "base-bash-libs-demo" if identifier == beacon else name
        packages.append({
            "SPDXID": identifier, "name": name, "versionInfo": release,
            "downloadLocation": f"https://github.com/basefoundry/{repo}/releases/tag/v{release}",
            "filesAnalyzed": True,
            "packageVerificationCode": {"packageVerificationCodeValue": hashlib.sha1("".join(sorted(hashes[identifier])).encode()).hexdigest()},
            "licenseConcluded": "Apache-2.0", "licenseDeclared": "Apache-2.0",
            "externalRefs": [{"referenceCategory": "OTHER", "referenceType": "source-commit", "referenceLocator": source}],
        })
    return {
        "spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0", "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"beacon-v{version}-sbom",
        "documentNamespace": f"https://github.com/basefoundry/base-bash-libs-demo/releases/v{version}/{commit}",
        "creationInfo": {"created": "1970-01-01T00:00:00Z", "creators": ["Tool: base-bash-libs-demo/release-artifact"]},
        "packages": packages, "files": files, "relationships": relationships,
    }


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key: " + key)
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(), object_pairs_hook=unique_object)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checksum_inventory(path):
    entries = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        require(match is not None, "malformed checksum record")
        value, name = match.groups()
        require(name not in entries, "duplicate checksum record")
        require(all(part not in ("", ".", "..") for part in name.split("/")), "unsafe checksum path")
        entries[name] = value
    require(bool(entries), "empty checksum inventory")
    return entries


def provenance(version, commit, framework_version, framework_commit, archive_name, archive_sha):
    return {
        "_type": "https://in-toto.io/Statement/v1",
        "subject": [{"name": archive_name, "digest": {"sha256": archive_sha}}],
        "predicateType": "https://slsa.dev/provenance/v1",
        "predicate": {
            "buildDefinition": {
                "buildType": "https://github.com/basefoundry/base-bash-libs-demo/release-artifact/v1",
                "externalParameters": {"version": version, "sourceCommit": commit, "dirtyState": "clean", "frameworkVersion": framework_version, "frameworkCommit": framework_commit},
                "resolvedDependencies": [
                    {"uri": "git+https://github.com/basefoundry/base-bash-libs-demo.git", "digest": {"sha1": commit}},
                    {"uri": "git+https://github.com/basefoundry/base-bash-libs.git", "digest": {"sha1": framework_commit}},
                ],
            },
            "runDetails": {"builder": {"id": "base-bash-libs-demo/release-artifact"}, "metadata": {"reproducible": True}},
        },
    }


def verify(output, destination):
    require(destination.is_dir() and not destination.is_symlink() and not any(destination.iterdir()), "extraction destination must be an empty owned directory")
    archives = list(output.glob("beacon-v*.tar.gz"))
    require(len(archives) == 1, "expected one Beacon archive")
    archive = archives[0]
    match = re.fullmatch(r"beacon-v((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-(?:alpha|beta|rc)\.[1-9][0-9]*)?)\.tar\.gz", archive.name)
    require(match is not None, "invalid archive version")
    version = match[1]
    stem = "beacon-v" + version
    names = {stem + suffix for suffix in (".tar.gz", ".spdx.json", ".provenance.json", ".SHA256SUMS")}
    require({p.name for p in output.iterdir()} == names, "unexpected or missing evidence asset")
    require(all((output / name).is_file() and not (output / name).is_symlink() for name in names), "evidence must be regular files")
    checksums = checksum_inventory(output / (stem + ".SHA256SUMS"))
    require(set(checksums) == names - {stem + ".SHA256SUMS"}, "incorrect evidence checksum inventory")
    require(all(digest(output / name) == value for name, value in checksums.items()), "evidence checksum mismatch")
    supplied_sbom = read_json(output / (stem + ".spdx.json"))
    supplied_provenance = read_json(output / (stem + ".provenance.json"))

    # Check every header before creating any payload file. Never use extractall,
    # and never interpret a link, device, directory, sparse, or extended member.
    with tarfile.open(archive, "r:gz") as tar:
        members = tar.getmembers()
        require(0 < len(members) <= 10000, "unsupported archive entry count")
        require(sum(m.size for m in members) <= 128 * 1024 * 1024, "archive exceeds size limit")
        paths = set()
        for member in members:
            parts = member.name.split("/")
            require(member.isfile() and not member.issparse() and not member.pax_headers, "unsupported archive entry type")
            require(member.mode in (0o644, 0o755), "unsupported archive mode")
            require(0 <= member.size <= 16 * 1024 * 1024, "unsupported archive file size")
            require(len(parts) > 1 and parts[0] == stem and all(p not in ("", ".", "..") for p in parts), "unsafe archive path")
            require(not any(ord(c) < 32 or ord(c) == 127 for c in member.name), "control character in archive path")
            require(member.name not in paths, "duplicate archive entry")
            paths.add(member.name)
        require(all(not any("/".join(name.split("/")[:i]) in paths for i in range(1, len(name.split("/")))) for name in paths), "file/directory archive conflict")
        for member in members:
            target = destination / member.name
            target.parent.mkdir(parents=True, exist_ok=True)
            with tar.extractfile(member) as source:
                target.write_bytes(source.read())
            target.chmod(member.mode)
    root = destination / stem
    required = ("BEACON.release", "VERSION", "LICENSE", "README.md", "base-bash-libs.lock", "bin/beacon", "lib/beacon.sh", "scripts/release-artifact", "scripts/artifact-evidence.py", "scripts/verify-vendor")
    require(all((root / name).is_file() for name in required), "missing required payload")
    identity = metadata(root / "BEACON.release")
    lock = metadata(root / "base-bash-libs.lock")
    commit, framework_commit = identity["commit"], lock["commit"]
    framework_version = lock["version"]
    require(re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-(?:alpha|beta|rc)\.[1-9][0-9]*)?", framework_version), "invalid framework version")
    require(lock["asset"] == f"base-bash-libs-v{framework_version}.tar.gz", "invalid framework asset name")
    require(re.fullmatch("[0-9a-f]{40}", commit) and re.fullmatch("[0-9a-f]{40}", framework_commit), "invalid full source identity")
    require(identity == {"schema_version": "1", "version": version, "commit": commit, "dirty_state": "clean", "provenance": "release-artifact", "framework_version": framework_version, "framework_commit": framework_commit}, "incoherent release identity")
    require((root / "VERSION").read_text().strip() == version, "VERSION mismatch")
    require(json.dumps(supplied_sbom, sort_keys=True) == json.dumps(sbom(root, version, commit), sort_keys=True), "SPDX evidence differs from actual archive inventory or identity")
    require(json.dumps(supplied_provenance, sort_keys=True) == json.dumps(provenance(version, commit, framework_version, framework_commit, archive.name, digest(archive)), sort_keys=True), "provenance differs from archive subject or source dependencies")
    vendor = root / "vendor/base-bash-libs"
    require(digest(vendor / "MANIFEST.sha256") == lock["manifest_sha256"], "vendor manifest differs from lock")
    inventory = checksum_inventory(vendor / "MANIFEST.sha256")
    expected_vendor = {p.relative_to(vendor).as_posix() for p in vendor.rglob("*") if p.is_file()} - {"MANIFEST.sha256", "BUNDLE.release"}
    require(set(inventory) == expected_vendor, "vendor inventory mismatch")
    require(all(digest(vendor / name) == value for name, value in inventory.items()), "vendor payload mismatch")
    bundle = metadata(vendor / "BUNDLE.release")
    runtime = metadata(vendor / "lib/bash/base-bash-libs.release")
    require(bundle["source_version"] == runtime["version"] == framework_version and bundle["source_commit"] == runtime["commit"] == framework_commit, "vendor identity mismatch")
    evidence = root / "vendor/evidence"
    upstream = checksum_inventory(evidence / f"base-bash-libs-v{framework_version}.SHA256SUMS")
    require(upstream[lock["asset"]] == lock["asset_sha256"], "vendor asset digest mismatch")
    for name, value in upstream.items():
        if name.endswith((".spdx.json", ".provenance.json")):
            require(digest(evidence / name) == value, "vendor evidence checksum mismatch")
    source_path = str(Path(__file__).resolve().parent.parent).encode()
    require(all(source_path not in p.read_bytes() for p in root.rglob("*") if p.is_file()), "absolute source path in payload")


if __name__ == "__main__":
    try:
        if len(sys.argv) == 5 and sys.argv[1] == "sbom":
            json.dump(sbom(Path(sys.argv[2]), sys.argv[3], sys.argv[4]), sys.stdout, indent=2)
            print()
        elif len(sys.argv) == 4 and sys.argv[1] == "verify":
            verify(Path(sys.argv[2]), Path(sys.argv[3]))
        else:
            sys.exit("usage: artifact-evidence.py sbom ROOT VERSION COMMIT | verify ASSETS DESTINATION")
    except (ValueError, OSError, KeyError, tarfile.TarError) as error:
        sys.exit(f"Artifact evidence error: {error}")
