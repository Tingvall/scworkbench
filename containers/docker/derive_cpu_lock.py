#!/usr/bin/env python3
"""Derive the Docker CPU lock from the qualified CUDA lock."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re


SOURCE_SHA256 = "183e8723406d547b7d6897a64450110fed9be4732fc1545617138e3042d9d416"
PIN = re.compile(r"^([A-Za-z0-9_.-]+)==([^\s;]+)$")
DROP = {"triton"}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def derive(source: pathlib.Path) -> str:
    raw = source.read_bytes()
    observed = digest(raw)
    if observed != SOURCE_SHA256:
        raise SystemExit(
            f"CUDA lock identity changed: expected {SOURCE_SHA256}, observed {observed}"
        )

    output: list[str] = []
    removed: list[str] = []
    replaced_torch = False
    replaced_index = False
    for raw_line in raw.decode("utf-8").splitlines():
        line = raw_line.strip()
        if line == "--extra-index-url https://download.pytorch.org/whl/cu124":
            output.append("--extra-index-url https://download.pytorch.org/whl/cpu")
            replaced_index = True
            continue
        match = PIN.fullmatch(line)
        if match:
            name, version = match.groups()
            normalized = re.sub(r"[-_.]+", "-", name).lower()
            if normalized.startswith("nvidia-") or normalized in DROP:
                removed.append(normalized)
                continue
            if normalized == "torch":
                if version != "2.6.0+cu124":
                    raise SystemExit(f"Unexpected CUDA torch pin: {version}")
                output.append(f"{name}==2.6.0+cpu")
                replaced_torch = True
                continue
        output.append(raw_line)

    if not replaced_index or not replaced_torch:
        raise SystemExit("CPU lock derivation did not replace both index and torch pin")
    if len(removed) != 14:
        raise SystemExit(f"Expected 14 CUDA-only packages, removed {len(removed)}")
    if len(removed) != len(set(removed)):
        raise SystemExit("Duplicate CUDA-only package encountered")

    result = "\n".join(output) + "\n"
    if "cu124" in result or "nvidia-" in result or "triton==" in result:
        raise SystemExit("CUDA-only content remained in derived CPU lock")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("destination", type=pathlib.Path)
    args = parser.parse_args()
    result = derive(args.source)
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    args.destination.write_text(result, encoding="utf-8")
    print(f"CPU Python lock SHA-256: {digest(result.encode('utf-8'))}")


if __name__ == "__main__":
    main()
