#!/usr/bin/env python3
"""Validate the installed Python runtime against the composite release lock."""

from __future__ import annotations

import argparse
import importlib.metadata
import pathlib
import re
import tomllib


PIN = re.compile(r"^([A-Za-z0-9_.-]+)==([^\s;]+)$")


def normalized(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def read_requirements(path: pathlib.Path) -> dict[str, tuple[str, str]]:
    pins: dict[str, tuple[str, str]] = {}
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("--"):
            continue
        match = PIN.fullmatch(line)
        if match is None:
            raise SystemExit(f"Unpinned Python requirement at {path}:{line_number}: {line}")
        key = normalized(match.group(1))
        if key in pins:
            raise SystemExit(f"Duplicate Python requirement: {match.group(1)}")
        pins[key] = (match.group(1), match.group(2))
    if not pins:
        raise SystemExit("Python requirement lock is empty")
    return pins


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--requirements", required=True, type=pathlib.Path)
    parser.add_argument("--pybench", required=True, type=pathlib.Path)
    args = parser.parse_args()

    pins = read_requirements(args.requirements)
    failures: list[str] = []
    for _, (name, expected) in sorted(pins.items()):
        try:
            observed = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            observed = "<missing>"
        if observed != expected:
            failures.append(f"{name} expected={expected} observed={observed}")

    pyproject = tomllib.loads(args.pybench.read_text(encoding="utf-8"))
    pybench_expected = pyproject["project"]["version"]
    try:
        pybench_observed = importlib.metadata.version("pybench")
    except importlib.metadata.PackageNotFoundError:
        pybench_observed = "<missing>"
    if pybench_observed != pybench_expected:
        failures.append(
            f"pybench expected={pybench_expected} observed={pybench_observed}"
        )

    if failures:
        raise SystemExit("Python runtime lock mismatch: " + "; ".join(failures))
    print(f"Python runtime lock OK: {len(pins)} packages; pybench={pybench_observed}")


if __name__ == "__main__":
    main()
