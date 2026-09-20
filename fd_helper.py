import os
import subprocess
import sys
from pathlib import Path

work_dir = Path(os.environ["WORK_DIR"]).resolve()
agentsignore = Path(os.environ["AGENTSIGNORE"]).resolve()


def run_fd(*extra_args):
    """
    Enumerate filesystem leaf entries.

    -I is essential on both scans. Without it, nested ignore files such as
    .venv/.gitignore can make the unrestricted scan incomplete.

    Files and symlinks are compared because directories themselves do not
    determine whether mounting a directory exposes extra files.
    """
    command = [
        "fdfind",
        "-0",
        "-I",
        "-H",
        "--type", "f",
        "--type", "l",
        *extra_args,
        ".",
        str(work_dir),
    ]

    try:
        result = subprocess.run(
            command,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as exc:
        sys.stderr.buffer.write(exc.stderr)
        raise

    paths = set()

    for raw_path in result.stdout.split(b"\0"):
        if not raw_path:
            continue

        path = Path(os.fsdecode(raw_path))

        if not path.is_absolute():
            path = work_dir / path

        try:
            relative = path.resolve(strict=False).relative_to(work_dir)
        except ValueError:
            # Ignore anything resolving outside work_dir.
            continue

        if relative != Path("."):
            paths.add(relative)

    return paths


# Files visible after applying .agentsignore.
included_files = run_fd("--ignore-file", str(agentsignore))

# Every file physically present under work_dir.
all_files = run_fd()

# Defensive consistency check.
unexpected = included_files - all_files
if unexpected:
    print(
        "Error: filtered scan returned entries absent from full scan:",
        file=sys.stderr,
    )
    for path in sorted(unexpected, key=lambda p: os.fsencode(str(p))):
        print(f"  {path}", file=sys.stderr)
    sys.exit(1)


def path_sort_key(path):
    return os.fsencode(str(path))


# Determine which directories exist from the parent chains of all files.
directories = {Path(".")}

for path in all_files:
    directories.update(path.parents)


# Number of total and included files beneath each directory.
all_count = {directory: 0 for directory in directories}
included_count = {directory: 0 for directory in directories}

for path in all_files:
    for parent in path.parents:
        all_count[parent] += 1

for path in included_files:
    for parent in path.parents:
        included_count[parent] += 1


def is_clean_directory(directory):
    """
    A directory is clean when:

    1. It contains at least one included file.
    2. Every file beneath it is included.

    Mounting such a directory cannot expose an ignored file.
    """
    return (
        included_count.get(directory, 0) > 0
        and included_count.get(directory, 0) == all_count.get(directory, 0)
    )


# Build direct-child indexes. We only need branches containing included files.
child_directories = {}
child_files = {}

for directory in directories:
    if directory == Path("."):
        continue

    child_directories.setdefault(directory.parent, []).append(directory)

for path in included_files:
    child_files.setdefault(path.parent, []).append(path)

for children in child_directories.values():
    children.sort(key=path_sort_key)

for children in child_files.values():
    children.sort(key=path_sort_key)


mounts = []


def collect(directory):
    # Select the highest clean directory. Its descendants then need no
    # individual mount entries.
    if directory != Path(".") and is_clean_directory(directory):
        mounts.append(directory)
        return

    # If the work directory itself is entirely clean, output ".".
    if directory == Path(".") and is_clean_directory(directory):
        mounts.append(directory)
        return

    for file_path in child_files.get(directory, ()):
        mounts.append(file_path)

    for child_directory in child_directories.get(directory, ()):
        if included_count.get(child_directory, 0) > 0:
            collect(child_directory)


collect(Path("."))

for path in sorted(mounts, key=path_sort_key):
    print("." if path == Path(".") else str(path))
