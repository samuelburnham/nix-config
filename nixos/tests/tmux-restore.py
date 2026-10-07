"""Focused restore checks: python3 tmux-restore.py <evaluated-config.json>."""

import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import threading
import time

sys.dont_write_bytecode = True


def check_process_sessions(root):
    source = Path(__file__).resolve().parents[1] / "home/modules/tmux/codex-process-session.py"
    spec = importlib.util.spec_from_file_location("codex_session", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    home = root / "codex home"
    sessions = home / "sessions"
    sessions.mkdir(parents=True)
    proc = root / "proc"
    ids = [f"00000000-0000-4000-8000-{i:012d}" for i in range(1, 5)]
    paths = []
    for index, sid in enumerate(ids):
        path = sessions / f"rollout-{sid}.jsonl"
        source = "cli" if index != 2 else {"subagent": {"other": "guardian"}}
        path.write_text(json.dumps({"type": "session_meta", "payload": {
            "id": sid, "source": source, "cwd": "/same/project"
        }}) + "\n")
        paths.append(path)
    for pid, transcript in [(100, paths[0]), (200, paths[1])]:
        process = proc / str(pid)
        (process / "fd").mkdir(parents=True)
        (process / "stat").write_text(f"{pid} (codex) " + " ".join(["1"] * 20))
        (process / "environ").write_bytes(b"CODEX_HOME=" + os.fsencode(home) + b"\0")
        (process / "fd/1").symlink_to(transcript)
        (process / "fd/2").symlink_to(paths[2])
    assert module.process_session(100, proc) == ids[0]
    assert module.process_session(200, proc) == ids[1]
    (proc / "100/fd/3").symlink_to(paths[3])
    assert module.process_session(100, proc) is None, "Ambiguous roots must not be guessed"
    (proc / "200/fd/1").unlink()
    assert module.process_session(200, proc) is None, "A guardian is not a root session"
    assert module.process_session(999, proc) is None
    print("PASS: exact per-process Codex IDs, guardian exclusion, ambiguity and missing processes", flush=True)


def check_boot(config, root):
    tmux = config["tmux"] + "/bin/tmux"
    sesh = config["sesh"] + "/bin/sesh"
    order = config["order"] + "/bin/tmux-session-order"
    resume = config["resume"] + "/bin/assistant-resume"
    resurrect = config["resurrect"] + "/share/tmux-plugins/resurrect"
    continuum = config["continuum"] + "/share/tmux-plugins/continuum"
    snapshots = root / "snapshots"
    snapshots.mkdir()
    binary = root / "bin"
    binary.mkdir()
    home = root / "home"
    home.mkdir()
    launches = root / "launches"
    launches.mkdir()
    shell = "/run/current-system/sw/bin/bash"
    for tool in ["claude", "codex"]:
        program = binary / tool
        program.write_text(f"#!{shell}\n"
                           'if [[ " $* " == *" --help "* ]]; then\n'
                           '  printf "  --resume <ID>\\n  --plugin-dir <PATH>...\\n  --model <MODEL>\\n"\n'
                           '  exit 0\n'
                           'fi\n'
                           'printf "%s\\n" "$*" >> "$TEST_LAUNCHES/${TMUX_PANE}.log"\n'
                           f"exec -a {tool} {shell} -c 'sleep 120'\n")
        program.chmod(0o755)

    env = os.environ.copy()
    for name in ["TMUX", "TMUX_PANE", "TMUX_RESURRECT_DIR", "TMUX_ASSISTANT_RESURRECT_DIR"]:
        env.pop(name, None)
    env.update(HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
               XDG_DATA_HOME=str(home / ".local/share"), XDG_STATE_HOME=str(home / ".local/state"),
               XDG_RUNTIME_DIR=str(root / "runtime"), TERM="xterm-256color", TEST_LAUNCHES=str(launches))
    env["PATH"] = f"{binary}:{Path(tmux).parent}:{env['PATH']}"
    Path(env["XDG_RUNTIME_DIR"]).mkdir()
    socket = str(root / "tmux.sock")
    base = [tmux, "-S", socket]
    client = None

    def run(*args, check=True, timeout=15):
        result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=timeout)
        if check and result.returncode:
            raise AssertionError(f"{args}: {result.stdout}\n{result.stderr}")
        return result.stdout.strip()

    def command(*args, **kwargs):
        return run(*base, *args, **kwargs)

    def wait_for(predicate, seconds=10):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.05)
        raise AssertionError("Timed out waiting for restore")

    common = (f"set -g @resurrect-dir {shlex.quote(str(snapshots))}\n"
              f"set -g default-shell {shell}\n"
              f"set -g default-command '{shell} --noprofile --norc'\n"
              + config["hooks"])
    initial = root / "initial.conf"
    initial.write_text(common)
    expected = ["zeta", "alpha-long", "alpha", "two words"]
    ids = [f"00000000-0000-4000-8000-{i:012d}" for i in range(1, 5)]
    try:
        for name in reversed(expected):
            command("-f", str(initial), "new-session", "-d", "-s", name, "-c", str(root))
        pid = command("display-message", "-p", "#{pid}")
        env["TMUX"] = f"{socket},{pid},0"
        for index, name in enumerate(reversed(expected), 1):
            command("set-option", "-t", "=" + name + ":", "@sesh-last-attached", str(index))
        run("bash", resurrect + "/scripts/save.sh", "quiet")
        records = (snapshots / "last").read_text().splitlines()
        assert [line.split("\t", 1)[1] for line in records if line.startswith("sesh-order\t")] == expected
        entries = []
        for index, name in enumerate(expected):
            tool = "codex" if index % 2 else "claude"
            entries.append(dict(pane=f"{name}:0.0", session_name=name, window_index="0", pane_index="0",
                                tool=tool, session_id=ids[index], cwd=str(root),
                                cli_args="--plugin-dir /stale/plugin --model test-model" if tool == "claude" else ""))
            if tool == "claude":
                project = re.sub("[^a-zA-Z0-9]", "-", str(root))
                transcript = home / ".claude/projects" / project / f"{ids[index]}.jsonl"
                transcript.parent.mkdir(parents=True, exist_ok=True)
                transcript.write_text("{}\n")
        save_script = re.search(r"bash '([^']+/scripts/save-assistant-sessions.sh)'", config["hooks"]).group(1)
        lookup = 'source "$1"; get_claude_session 999999999 "$2" "$3"'
        assert not run("bash", "-c", lookup, "claude-lookup", save_script, "claude", str(root)), \
            "A missing Claude process record must not select another pane's transcript"
        assert run("bash", "-c", lookup, "claude-lookup", save_script,
                   f"claude --resume {ids[0]}", str(root)) == ids[0]
        print("PASS: Claude keeps explicit session IDs and never guesses from a shared directory", flush=True)
        (snapshots / "assistant-sessions.json").write_text(json.dumps({"sessions": entries}))
        command("kill-server")
        wait_for(lambda: not Path(f"/proc/{pid}").exists() or "\nState:\tZ" in Path(f"/proc/{pid}/status").read_text())
        env.pop("TMUX")

        boot = root / "boot.conf"
        boot.write_text(common + f"run-shell {resurrect}/resurrect.tmux\n"
                        "set -g @continuum-restore on\n"
                        f"run-shell {continuum}/continuum.tmux\n"
                        # Auto-restore must work before later plugins finish loading.
                        "run-shell 'sleep 2'\n")
        command("-f", str(boot), "new-session", "-d", "-s", "bootstrap", "-c", str(root))
        pid = command("display-message", "-p", "#{pid}")
        env["TMUX"] = f"{socket},{pid},0"
        wait_for(lambda: command("show-option", "-gqv", "@assistant-layout-restored") == "on")
        # Initial bootstrap sessions are outside the saved layout.
        command("kill-session", "-t", "=bootstrap", check=False)
        assert run(sesh, "list", "-t").splitlines() == expected
        assert not list(launches.iterdir()), "Clientless boot must defer assistant startup"
        print("PASS: real continuum cold start restores MRU before slow plugins finish", flush=True)

        started = time.monotonic()
        client = subprocess.Popen(base + ["-C", "attach-session", "-t", "=" + expected[0]], env=env,
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        reader = threading.Thread(target=client.stdout.read, daemon=True)
        reader.start()
        competitors = [subprocess.Popen([resume, "--boot"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) for _ in range(2)]
        wait_for(lambda: command("show-option", "-gqv", "@assistants_resumed") == "on")
        wait_for(lambda: len(list(launches.iterdir())) == len(entries))
        elapsed = time.monotonic() - started
        for process in competitors:
            assert process.wait(timeout=5) == 0
        actual = [path.read_text().splitlines() for path in launches.iterdir()]
        assert all(len(lines) == 1 for lines in actual), actual
        assert sorted(lines[0].split()[-1] for lines in actual) == sorted(ids), actual
        assert all("--plugin-dir" not in lines[0] for lines in actual), actual
        assert sum("--model test-model" in lines[0] for lines in actual) == 2, actual
        assert elapsed < 10, f"Restore still waits per detached session: {elapsed:.2f}s"
        print(f"PASS: four exact Claude/Codex resumes in {elapsed:.2f}s, no duplicate launches", flush=True)

        client_name = command("list-clients", "-F", "#{client_name}")
        for name in ["alpha", "alpha-long"]:
            command("switch-client", "-c", client_name, "-t", "=" + name)
        expected_after = ["alpha-long", "alpha", "zeta", "two words"]
        assert run(sesh, "list", "-t").splitlines() == expected_after
        run(sesh, "last")
        assert command("list-clients", "-F", "#{session_name}") == "alpha"
        print("PASS: rapid visits have distinct MRU ranks and sesh last is correct", flush=True)
    except Exception:
        log = snapshots / "assistant-restore.log"
        if log.exists():
            print(log.read_text(), file=sys.stderr)
        for pane in command("list-panes", "-a", "-F", "#{pane_id}", check=False).splitlines():
            print(pane, command("capture-pane", "-p", "-t", pane, check=False), file=sys.stderr)
        raise
    finally:
        command("kill-server", check=False)
        if client is not None:
            client.wait(timeout=5)


if __name__ == "__main__":
    config = json.loads(Path(sys.argv[1]).read_text())
    with tempfile.TemporaryDirectory(prefix="tmux-restore-test-") as directory:
        root = Path(directory)
        check_process_sessions(root)
        check_boot(config, root)
