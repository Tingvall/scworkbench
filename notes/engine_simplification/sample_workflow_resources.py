"""Read-only sampler, launched explicitly by the final-gate supervisor.

Usage: python3 sample_workflow_resources.py R_PID NEW_CHAMBER NEW_OUTPUT.csv [R_TMP_ROOT]
Does not start the workflow or any background jobs. Five-second disk samples
are lower bounds on transient peaks; GNU time remains the peak-RSS authority.
Only explicit owned roots are walked, without following symbolic links.
"""

import csv
import os
from pathlib import Path
import stat
import sys
import time


def proc_fields(path):
    result = {}
    for line in path.read_text().splitlines():
        key, _, value = line.partition(":")
        result[key] = value.strip().split()[0] if value.strip() else ""
    return result


def sample(pid, roots):
    status = proc_fields(Path(f"/proc/{pid}/status"))
    io = proc_fields(Path(f"/proc/{pid}/io"))
    seen = set()
    logical = allocated = files = 0
    for root in roots:
        for directory, _, names in os.walk(root, followlinks=False):
            for name in names:
                try:
                    info = os.lstat(Path(directory) / name)
                except OSError:
                    continue
                key = info.st_dev, info.st_ino
                if not stat.S_ISREG(info.st_mode) or key in seen:
                    continue
                seen.add(key)
                logical += info.st_size
                allocated += info.st_blocks * 512
                files += 1
    return [status.get("VmRSS", ""), status.get("VmHWM", ""),
            status.get("VmPeak", ""), io.get("rchar", ""),
            io.get("wchar", ""), io.get("read_bytes", ""),
            io.get("write_bytes", ""), logical, allocated, files]


if __name__ == "__main__":
    if len(sys.argv) not in (4, 5):
        raise SystemExit(__doc__)
    pid = int(sys.argv[1])
    roots = [Path(sys.argv[2]).resolve()]
    if len(sys.argv) == 5:
        roots.append(Path(sys.argv[4]).resolve())
    if any(root == Path("/") or not root.is_dir() for root in roots):
        raise SystemExit("Sampling requires existing explicit owned roots, not /")
    proc = Path(f"/proc/{pid}")
    initial = (proc / "stat").read_text().rsplit(")", 1)[1].split()[19]
    started = time.monotonic()
    with Path(sys.argv[3]).open("x", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["elapsed_seconds", "rss_kib", "hwm_kib", "vmpeak_kib",
                         "rchar", "wchar", "read_bytes", "write_bytes",
                         "sampled_logical_bytes", "sampled_allocated_bytes", "files"])
        while proc.exists():
            try:
                if (proc / "stat").read_text().rsplit(")", 1)[1].split()[19] != initial:
                    break
                values = sample(pid, roots)
            except (FileNotFoundError, ProcessLookupError):
                break
            writer.writerow([round(time.monotonic() - started, 3), *values])
            stream.flush()
            time.sleep(5)
