#!/usr/bin/env python3
"""Render the Apptainer %post recipe as the Docker installation script."""

from __future__ import annotations

import argparse
import pathlib


SOURCE_LOCK = "containers/apptainer/fullstack_python_requirements.lock"
CPU_LOCK = "containers/docker/fullstack_python_requirements.cpu.lock"


def post_section(definition: pathlib.Path) -> str:
    lines = definition.read_text(encoding="utf-8").splitlines()
    try:
        start = lines.index("%post") + 1
    except ValueError as error:
        raise SystemExit(f"No %post section in {definition}") from error
    end = next(
        (index for index in range(start, len(lines)) if lines[index].startswith("%")),
        len(lines),
    )
    body = "\n".join(lines[start:end]).strip("\n") + "\n"
    if not body.strip():
        raise SystemExit(f"Empty %post section in {definition}")
    return body


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("definition", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()

    body = post_section(args.definition).replace(SOURCE_LOCK, CPU_LOCK)
    if SOURCE_LOCK in body or CPU_LOCK not in body:
        raise SystemExit("Python lock path substitution failed")
    rendered = "#!/usr/bin/env bash\n# Generated from the Apptainer %post section.\n" + body
    args.output.write_text(rendered, encoding="utf-8")
    args.output.chmod(0o755)


if __name__ == "__main__":
    main()
