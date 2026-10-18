"""Read-only parity/accounting for the frozen pair; no protocol generation."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

core, python = map(Path, sys.argv[1:])
roots = [core / "inst/protocol", python / "protocol"]
files = []
for root in roots:
    assert not any(path.is_symlink() for path in root.rglob("*"))
    files.append({str(path.relative_to(root)): path for path in root.rglob("*")
                  if path.is_file()})
extra = "pybench-op-v4-python-runtime.schema.json"
assert len(files[0]) == 44 and len(files[1]) == 45
assert set(files[1]) - set(files[0]) == {extra}
assert not set(files[0]) - set(files[1])
rows = []
for name in sorted(files[0]):
    left, right = [mapping[name].read_bytes() for mapping in files]
    assert left == right, name
    rows.append({"path": name, "sha256": hashlib.sha256(left).hexdigest()})
assert hashlib.sha256(files[1][extra].read_bytes()).hexdigest() == (
    "b2ae886b2c3095159f9bb07de6a826f4e14498481600b6e2bb9656cd65637857")
assert not subprocess.check_output(["git", "-C", str(core), "diff", "--name-only",
    "8f53e950e6eda4c86b0f4ce6623bc14a1f2e637e", "--", "inst/protocol"])
print(json.dumps({"shared_files": rows, "shared_count": len(rows),
    "python_only": extra, "identities_changed": False}, indent=2))
print("FROZEN_PROTOCOL_PARITY 44/44 PASS; Python-only runtime schema unchanged")
