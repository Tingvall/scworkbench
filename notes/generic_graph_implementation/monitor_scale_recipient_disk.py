"""External, read-only Linux disk sampler for the owned scale subprocesses.

This is qualification instrumentation, not an engine or a pack callback. Time-v
remains the authoritative per-process RSS measurement. Sampling cannot prove
that a short-lived file between samples did not exist.
"""

import argparse
import csv
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def descendants(parent):
    links = {}
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            fields = (entry / "stat").read_text().rsplit(")", 1)[1].split()
            links[int(entry.name)] = int(fields[1])
        except (OSError, ValueError, IndexError):
            continue
    selected = {parent}
    changed = True
    while changed:
        added = {pid for pid, owner in links.items() if owner in selected}
        changed = not added.issubset(selected)
        selected |= added
    return selected


def category(name):
    if "(deleted)" in name or "etilqs" in name:
        return "unlinked_or_sqlite_temp"
    if name.endswith(("-wal", "-shm", "-journal")):
        return "sqlite_journal_wal_shm"
    if name.endswith((".sqlite", ".db")):
        return "sqlite_main"
    if "scwb_graph_identity_" in name or "scwb_graph_tokens_" in name:
        return "canonical_tokens"
    if name.endswith((".ndjson", ".jsonl")):
        return "transport"
    return "other_owned"


def sample(root, processes, temp_roots):
    # De-duplicate by device/inode: a file in a directory and an open fd count
    # once. fstat-like fd stat still observes allocated blocks of unlinked files.
    files = {}

    def retain(path, name):
        try:
            state = path.stat()
            if not path.is_file():
                return
            files[(state.st_dev, state.st_ino)] = (
                name, state.st_size, state.st_blocks * 512
            )
        except OSError:
            pass  # Process/file may have ended between enumeration and stat.

    for pid in processes:
        try:
            descriptors = list((Path("/proc") / str(pid) / "fd").iterdir())
        except OSError:
            continue
        for descriptor in descriptors:
            try:
                name = os.readlink(descriptor)
            except OSError:
                continue
            if name.startswith("/tmp/Rtmp"):
                temp_roots.add(Path("/tmp") / Path(name).parts[2])
            if name.startswith(str(root) + "/") or any(
                marker in name
                for marker in ("scwb_graph_", "scwb_object_meta_", "etilqs")
            ) or any(name.startswith(str(item) + "/") for item in temp_roots):
                retain(descriptor, name)
    for directory in {root} | temp_roots:
        for current, _, names in os.walk(directory):
            for name in names:
                path = Path(current) / name
                if not path.is_symlink():
                    retain(path, str(path))
    totals = {}
    for name, logical, allocated in files.values():
        values = totals.setdefault(category(name), [0, 0])
        values[0] += logical
        values[1] += allocated
    return sum(item[1] for item in files.values()), sum(
        item[2] for item in files.values()
    ), totals


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--owned-output", required=True, type=Path)
    parser.add_argument("--samples", required=True, type=Path)
    parser.add_argument("--existing-owned-output", action="store_true")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command or args.samples.exists() or (args.owned_output.exists() and not args.existing_owned_output):
        parser.error("command and fresh owned output/CSV paths required")
    args.samples.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    temporary_roots = set()
    peak_logical = peak_allocated = 0
    with args.samples.open("x", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow([
            "elapsed_seconds", "logical_bytes", "allocated_bytes",
            "filesystem_available_bytes", "categories_json",
        ])
        process = subprocess.Popen(command)
        while True:
            logical, allocated, categories = sample(
                args.owned_output, descendants(process.pid), temporary_roots
            )
            state = os.statvfs(args.owned_output.parent)
            available = state.f_bavail * state.f_frsize
            writer.writerow([
                round(time.monotonic() - start, 3), logical, allocated,
                available, json.dumps(categories, sort_keys=True),
            ])
            stream.flush()
            peak_logical = max(peak_logical, logical)
            peak_allocated = max(peak_allocated, allocated)
            result = process.poll()
            if result is not None:
                break
            time.sleep(0.5)
    print(
        "GRAPH_SCALE_DISK sampled_peak_logical_bytes=" + str(peak_logical)
        + " sampled_peak_allocated_bytes=" + str(peak_allocated)
        + " sample_interval_seconds=0.5 unlinked_open_fds_included=TRUE"
        + " short_lived_between_samples_may_be_missed=TRUE", flush=True
    )
    return result if result >= 0 else 128 - result


if __name__ == "__main__":
    sys.exit(main())
