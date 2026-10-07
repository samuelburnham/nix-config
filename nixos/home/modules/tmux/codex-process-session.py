"""Find the interactive Codex session whose rollout is open in a process."""

import json
import os
from pathlib import Path
import re
import stat
import sys


def process_session(pid, proc=Path("/proc")):
    process = proc / str(pid)
    try:
        # The start time distinguishes a process from a later reuse of its PID.
        identity = (process / "stat").read_text().rsplit(")", 1)[1].split()[19]
        environment = dict(
            item.split(b"=", 1)
            for item in (process / "environ").read_bytes().split(b"\0")
            if b"=" in item
        )
        home = Path(os.fsdecode(environment.get(b"HOME", os.fsencode(Path.home()))))
        codex_home = Path(os.fsdecode(environment.get(b"CODEX_HOME", os.fsencode(home / ".codex"))))
        if not codex_home.is_absolute():
            codex_home = (process / "cwd").resolve() / codex_home
        sessions = (codex_home / "sessions").resolve()
        descriptors = list((process / "fd").iterdir())
    except (OSError, IndexError, ValueError):
        return None

    candidates = set()
    for descriptor in descriptors:
        try:
            path = Path(os.readlink(descriptor))
            if not path.name.startswith("rollout-") or path.suffix != ".jsonl":
                continue
            path = path.resolve()
            if not path.is_relative_to(sessions) or not stat.S_ISREG(path.stat().st_mode):
                continue
            # Read the pathname, never a /proc fd that could be a pipe or device.
            with path.open(encoding="utf-8") as transcript:
                record = json.loads(transcript.readline(1024 * 1024))
            if not isinstance(record, dict) or record.get("type") != "session_meta":
                continue
            payload = record.get("payload")
            if not isinstance(payload, dict) or payload.get("source") != "cli":
                continue
            sid = payload.get("id")
            if isinstance(sid, str) and re.fullmatch(
                r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", sid
            ):
                candidates.add(sid)
        except (OSError, ValueError):
            continue

    try:
        current_identity = (process / "stat").read_text().rsplit(")", 1)[1].split()[19]
    except (OSError, IndexError):
        return None
    # Ambiguous ownership must not silently resume a different conversation.
    if identity == current_identity and len(candidates) == 1:
        return candidates.pop()
    return None


if __name__ == "__main__":
    session = process_session(int(sys.argv[1]))
    if session:
        print(session)
