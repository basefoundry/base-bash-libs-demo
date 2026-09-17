"""Deterministic Beacon SPDX evidence (standard library only)."""

import hashlib
import json
from pathlib import Path
import sys


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


if __name__ == "__main__":
    if len(sys.argv) != 5 or sys.argv[1] != "sbom":
        sys.exit("usage: artifact-evidence.py sbom ROOT VERSION COMMIT")
    json.dump(sbom(Path(sys.argv[2]), sys.argv[3], sys.argv[4]), sys.stdout, indent=2)
    print()
