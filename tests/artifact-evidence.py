"""Offline coherent-checksum evidence and archive regression fixtures."""
import copy
import hashlib
import io
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tarfile
import tempfile

repo = Path(__file__).resolve().parent.parent
original = Path(sys.argv[1])
archive_name = next(original.glob("*.tar.gz")).name
stem = archive_name.removesuffix(".tar.gz")
verifier = repo / "scripts/release-artifact"
count = 0


def sums(directory):
    names = [archive_name, stem + ".spdx.json", stem + ".provenance.json"]
    (directory / (stem + ".SHA256SUMS")).write_text("".join(
        hashlib.sha256((directory / name).read_bytes()).hexdigest() + "  " + name + "\n" for name in names))


def check(directory, success=False, message=None, smoke=False):
    global count
    command = [str(verifier), "verify", str(directory)]
    if smoke:
        command.append("--trusted-smoke")
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    assert (result.returncode == 0) == success, result.stdout + result.stderr
    if message:
        assert message in result.stderr, result.stderr
    count += 1


with tempfile.TemporaryDirectory(prefix="beacon-evidence-regressions-") as temporary:
    temp = Path(temporary)
    sbom_path = stem + ".spdx.json"
    provenance_path = stem + ".provenance.json"
    mutations = [
        (sbom_path, lambda d: d.update(files=[])),
        (sbom_path, lambda d: d["files"].pop()),
        (sbom_path, lambda d: d["files"].append(copy.deepcopy(d["files"][0]))),
        (sbom_path, lambda d: d["files"][0]["checksums"][1].update(checksumValue="0" * 64)),
        (sbom_path, lambda d: d["packages"][0].update(versionInfo="99.0.0")),
        (sbom_path, lambda d: d.update(relationships=[])),
        (provenance_path, lambda d: d["subject"][0]["digest"].update(sha256="0" * 64)),
        (provenance_path, lambda d: d["predicate"]["buildDefinition"]["resolvedDependencies"].pop()),
        (provenance_path, lambda d: d["predicate"]["buildDefinition"]["externalParameters"].update(sourceCommit="0" * 40)),
        (provenance_path, lambda d: d.update(subject=[], unrelated=json.dumps(d["subject"]))),
        (provenance_path, lambda d: d["predicate"]["runDetails"]["metadata"].update(reproducible=1)),
    ]
    for index, (name, mutate) in enumerate(mutations):
        directory = temp / f"json-{index}"
        shutil.copytree(original, directory)
        path = directory / name
        document = json.loads(path.read_text())
        mutate(document)
        path.write_text(json.dumps(document))
        sums(directory)
        check(directory, message="evidence" if name == sbom_path else "provenance")
    directory = temp / "duplicate-key"
    shutil.copytree(original, directory)
    path = directory / provenance_path
    path.write_text(path.read_text().replace('"predicateType":', '"predicateType": "unrelated", "predicateType":', 1))
    sums(directory)
    check(directory, message="duplicate JSON key")

    for kind in ("symlink", "hardlink", "fifo", "traversal", "absolute", "duplicate", "truncated"):
        directory = temp / kind
        shutil.copytree(original, directory)
        archive = directory / archive_name
        if kind == "truncated":
            archive.write_bytes(b"not a gzip archive")
        else:
            with tarfile.open(original / archive_name) as source, tarfile.open(archive, "w:gz", format=tarfile.USTAR_FORMAT) as target:
                members = source.getmembers()
                for member in members:
                    target.addfile(member, source.extractfile(member))
                entry = tarfile.TarInfo(stem + "/extra")
                entry.mode = 0o644
                if kind == "symlink":
                    entry.type, entry.linkname = tarfile.SYMTYPE, "synthetic-target"
                elif kind == "hardlink":
                    entry.type, entry.linkname = tarfile.LNKTYPE, stem + "/VERSION"
                elif kind == "fifo":
                    entry.type = tarfile.FIFOTYPE
                elif kind == "traversal":
                    entry.name = stem + "/../outside"
                elif kind == "absolute":
                    entry.name = "/synthetic-outside"
                else:
                    entry.name = members[0].name
                target.addfile(entry, io.BytesIO(b""))
        sums(directory)
        check(directory)
    directory = temp / "extra-asset"
    shutil.copytree(original, directory)
    (directory / "extra").write_text("synthetic")
    check(directory, message="unexpected")

    # A fully coherent synthetic executable proves default verify never runs it.
    directory = temp / "execution-boundary"
    shutil.copytree(original, directory)
    payload = temp / "payload"
    payload.mkdir()
    helper = runpy.run_path(str(repo / "scripts/artifact-evidence.py"))
    helper["verify"](directory, payload)
    root = payload / stem
    marker = temp / "executed"
    (root / "bin/beacon").write_text(f"#!/usr/bin/env bash\nprintf synthetic > '{marker}'\nexit 23\n")
    identity = helper["metadata"](root / "BEACON.release")
    (directory / sbom_path).write_text(json.dumps(helper["sbom"](root, identity["version"], identity["commit"])))
    with tarfile.open(directory / archive_name, "w:gz", format=tarfile.USTAR_FORMAT) as target:
        for path in sorted(p for p in root.rglob("*") if p.is_file()):
            target.add(path, arcname=stem + "/" + path.relative_to(root).as_posix(), recursive=False)
    document = json.loads((directory / provenance_path).read_text())
    document["subject"][0]["digest"]["sha256"] = hashlib.sha256((directory / archive_name).read_bytes()).hexdigest()
    (directory / provenance_path).write_text(json.dumps(document))
    sums(directory)
    check(directory, success=True)
    assert not marker.exists()
    check(directory, smoke=True)
    assert marker.read_text() == "synthetic"

print(f"Artifact semantic and archive regressions passed: {count}")
