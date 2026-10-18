"""Read-only sampled allocation, unique inodes, own chamber + R temporary root.

Samples are lower bounds, not filesystem quotas or proofs of transient maxima.
"""
import csv
import os
import stat
import sys
import time
from pathlib import Path

pid, chamber, output = int(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
roots = {chamber}
start = time.monotonic()
with output.open("x", newline="") as stream:
    writer = csv.writer(stream)
    writer.writerow(["elapsed_seconds", "allocated_bytes", "logical_bytes", "roots"])
    while Path(f"/proc/{pid}").exists():
        for fd in Path(f"/proc/{pid}/fd").iterdir():
            try:
                path = Path(os.readlink(fd))
                if len(path.parts) > 2 and path.parts[1] == "tmp" and path.parts[2].startswith("Rtmp"):
                    roots.add(Path(*path.parts[:3]))
            except (OSError, ValueError):
                pass
        seen = set()
        allocated = logical = 0
        for root in roots:
            for directory, _, files in os.walk(root, followlinks=False):
                for name in files:
                    try:
                        info = os.lstat(Path(directory) / name)
                    except OSError:
                        continue
                    key = (info.st_dev, info.st_ino)
                    if key in seen or not stat.S_ISREG(info.st_mode):
                        continue
                    seen.add(key)
                    allocated += info.st_blocks * 512
                    logical += info.st_size
        writer.writerow([round(time.monotonic() - start, 3), allocated, logical, ";".join(map(str, sorted(roots)))])
        stream.flush()
        time.sleep(1)
