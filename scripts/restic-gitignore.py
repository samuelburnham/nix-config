"""Collect untrusted Git paths separately from privileged exclusion encoding."""

import argparse
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile


MAX_BYTES = 64 * 1024 * 1024
GIT_TIMEOUT = 120
PRUNE_NAMES = {b".git", b".cache", b"node_modules", b".direnv"}


def checked_path(root, repo, relative):
    if not os.path.isabs(repo) or os.path.normpath(repo) != repo:
        raise ValueError("repository path must be absolute and normalized")
    if os.path.commonpath((root, repo)) != root:
        raise ValueError("repository path escapes the scan root")
    if b".git" in os.path.relpath(repo, root).split(b"/"):
        raise ValueError("repository path enters Git metadata")
    relative = relative.removesuffix(b"/")
    if not relative or any(part in (b"", b".", b"..", b".git") for part in relative.split(b"/")):
        raise ValueError("invalid ignored path or Git metadata exclusion")
    return os.path.join(repo, relative)


def literal_pattern(path):
    try:
        text = path.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if "\n" in text or "\r" in text:
        return None
    pattern = "".join(
        "\\" + char if char in "\\*?[]" else "$$" if char == "$" else char
        for char in text
    )
    # Restic trims surrounding whitespace before parsing the pattern.
    if pattern[-1].isspace():
        pattern = pattern[:-1] + "[" + pattern[-1] + "]"
    if len(pattern.encode("utf-8")) >= 65535:
        return None
    return pattern


def git_ignored(git, repo):
    command = [
        git,
        "--no-optional-locks",
        "-c", "core.fsmonitor=false",
        "-c", "core.hooksPath=/dev/null",
        "-c", "core.untrackedCache=false",
        "-c", "core.excludesFile=/dev/null",
        "-c", "core.bare=false",
        "-c", b"safe.directory=" + repo,
        b"--git-dir=" + os.path.join(repo, b".git"),
        b"--work-tree=" + repo,
        "ls-files", "--others", "--ignored", "--exclude-standard",
        "--directory", "--full-name", "-z",
    ]
    env = {
        "PATH": os.path.dirname(git),
        "HOME": "/nonexistent",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_TERMINAL_PROMPT": "0",
    }
    # The service's file-size limit also bounds subprocess output on disk.
    with tempfile.TemporaryFile() as output:
        subprocess.run(command, env=env, cwd=repo, stdout=output,
                       check=True, timeout=GIT_TIMEOUT)
        output.seek(0)
        data = output.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES or (data and not data.endswith(b"\0")):
        raise ValueError("oversized or incomplete Git output")
    return data[:-1].split(b"\0") if data else []


def scan(root, git, output):
    if not os.path.isdir(root) or os.path.islink(root):
        raise ValueError("scan root must be an existing directory, not a symlink")
    ignored_directories = set()
    emitted = 0

    def walk_error(error):
        raise error

    for repo, directories, files in os.walk(root, onerror=walk_error, followlinks=False):
        if b".git" in directories or b".git" in files:
            if os.path.islink(os.path.join(repo, b".git")):
                raise ValueError("symlinked .git metadata is unsupported")
            for relative in git_ignored(git, repo):
                path = checked_path(root, repo, relative)
                record = repo + b"\0" + relative + b"\0"
                emitted += len(record)
                if emitted > MAX_BYTES:
                    raise ValueError("Git exclusion manifest exceeds size limit")
                output.write(record)
                if relative.endswith(b"/"):
                    ignored_directories.add(path)
        directories[:] = [
            name for name in directories
            if name not in PRUNE_NAMES
            and os.path.join(repo, name) not in ignored_directories
        ]


def encode(root, manifest, destination):
    fd = os.open(manifest, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("manifest must be a regular file")
        data = stream.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES or (data and not data.endswith(b"\0")):
        raise ValueError("oversized or incomplete exclusion manifest")
    fields = data[:-1].split(b"\0") if data else []
    if len(fields) % 2:
        raise ValueError("incomplete repository/path pair")

    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8",
                                         dir=Path(destination).parent, delete=False) as stream:
            temporary = stream.name
            for repo, relative in zip(fields[::2], fields[1::2]):
                path = checked_path(root, repo, relative)
                pattern = literal_pattern(path)
                if pattern is None:
                    print(f"Keeping path with an unrepresentable exclusion: {path!r}", file=sys.stderr)
                    continue
                stream.write(pattern + "\n")
        os.replace(temporary, destination)
        temporary = None
    finally:
        if temporary is not None:
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    scan_parser = subparsers.add_parser("scan")
    scan_parser.add_argument("root")
    scan_parser.add_argument("git")
    encode_parser = subparsers.add_parser("encode")
    encode_parser.add_argument("root")
    encode_parser.add_argument("manifest")
    encode_parser.add_argument("destination")
    args = parser.parse_args()
    root = os.fsencode(os.path.abspath(args.root))
    try:
        if args.command == "scan":
            scan(root, args.git, sys.stdout.buffer)
        else:
            encode(root, args.manifest, args.destination)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Git backup filtering failed: {error}\n")


if __name__ == "__main__":
    main()
