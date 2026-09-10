#!/usr/bin/env python3
"""Validate bundled runtime notices and, optionally, installed identities."""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import pathlib
import subprocess


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_provenance(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def validate_files(root: pathlib.Path, manifest: dict) -> None:
    if manifest.get("schema") != "scworkbench.runtime-license-inventory.v1":
        raise SystemExit("Unsupported runtime license inventory schema")
    components = manifest.get("components")
    if not isinstance(components, list) or not components:
        raise SystemExit("Runtime license inventory has no components")

    for component in components:
        name = component.get("name", "<unnamed>")
        if not component.get("license_expression"):
            raise SystemExit(f"Missing license expression for {name}")
        files = component.get("files")
        if not isinstance(files, list) or not files:
            raise SystemExit(f"No license evidence files recorded for {name}")
        for record in files:
            source_urls = record.get("source_urls")
            if not isinstance(source_urls, list) or not source_urls:
                raise SystemExit(f"Missing upstream source URL for {name}")
            relative = pathlib.PurePosixPath(record["path"])
            if relative.is_absolute() or ".." in relative.parts:
                raise SystemExit(f"Unsafe license evidence path for {name}: {relative}")
            target = root.joinpath(*relative.parts)
            if not target.is_file():
                raise SystemExit(f"Missing license evidence for {name}: {target}")
            observed = sha256(target)
            if observed != record["sha256"]:
                raise SystemExit(
                    f"License evidence digest mismatch for {name}: "
                    f"expected={record['sha256']} observed={observed} path={target}"
                )


def r_bpcells_identity() -> tuple[str, str]:
    expression = (
        'd <- packageDescription("BPCells"); '
        'cat(as.character(d$Version), "\\n", as.character(d$RemoteSha), "\\n", sep="")'
    )
    result = subprocess.run(
        ["Rscript", "-e", expression],
        check=True,
        capture_output=True,
        text=True,
    )
    lines = result.stdout.splitlines()
    if len(lines) != 2:
        raise SystemExit("Could not read installed R BPCells identity")
    return lines[0], lines[1]


def validate_runtime(manifest: dict, profile: str, provenance_path: pathlib.Path) -> None:
    components = {component["name"]: component for component in manifest["components"]}
    bpcells = components["BPCells"]
    triton = components["Triton"]
    provenance = load_provenance(provenance_path)

    r_record = next(item for item in bpcells["installations"] if item["ecosystem"] == "R")
    r_version, r_ref = r_bpcells_identity()
    if r_version != r_record["version"] or r_ref != r_record["source_ref"]:
        raise SystemExit(
            "Installed R BPCells identity mismatch: "
            f"expected={r_record['version']}@{r_record['source_ref']} "
            f"observed={r_version}@{r_ref}"
        )

    python_record = next(
        item for item in bpcells["installations"] if item["ecosystem"] == "Python"
    )
    python_version = importlib.metadata.version("bpcells")
    if not python_version.startswith(python_record["version_prefix"]):
        raise SystemExit(
            "Installed Python BPCells version mismatch: "
            f"expected_prefix={python_record['version_prefix']} observed={python_version}"
        )
    if provenance.get("BPCELLS_PYTHON_UPSTREAM_REF") != python_record["source_ref"]:
        raise SystemExit("Installed Python BPCells source ref does not match license inventory")

    if profile == "apptainer":
        triton_record = next(
            item for item in triton["installations"] if profile in item["profiles"]
        )
        triton_version = importlib.metadata.version("triton")
        if triton_version != triton_record["version"]:
            raise SystemExit(
                "Installed Triton identity mismatch: "
                f"expected={triton_record['version']} observed={triton_version}"
            )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--license-root", required=True, type=pathlib.Path)
    parser.add_argument("--profile", choices=("apptainer", "docker"))
    parser.add_argument("--runtime", action="store_true")
    parser.add_argument("--provenance", type=pathlib.Path)
    args = parser.parse_args()

    root = args.license_root.resolve()
    manifest_path = root / "runtime_license_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    validate_files(root, manifest)

    if args.runtime:
        if args.profile is None or args.provenance is None:
            parser.error("--runtime requires --profile and --provenance")
        validate_runtime(manifest, args.profile, args.provenance)

    print(
        "Runtime license inventory: OK "
        f"({len(manifest['components'])} components; profile={args.profile or 'files-only'})"
    )


if __name__ == "__main__":
    main()
