"""Run with GIT and RESTIC pointing to the binaries used by the backup service."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/restic-gitignore.py"
SPEC = importlib.util.spec_from_file_location("restic_gitignore", SCRIPT)
helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper)
GIT = os.environ.get("GIT") or shutil.which("git")
RESTIC = os.environ.get("RESTIC") or shutil.which("restic")


class GitignoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repos = self.root / "repos"
        self.repos.mkdir()
        self.manifest = self.root / "manifest"
        self.excludes = self.root / "excludes"
        self.env = {
            "PATH": os.path.dirname(GIT),
            "HOME": str(self.root),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_NAME": "Fixture",
            "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "Fixture",
            "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
        }

    def git(self, *args, cwd=None):
        return subprocess.run(
            [GIT, "-c", "core.hooksPath=/dev/null", *args], env=self.env,
            cwd=cwd, capture_output=True, check=True, timeout=20,
        ).stdout

    def repo(self, name="project"):
        repo = self.repos / name
        self.git("init", "--quiet", "--template=", str(repo))
        (repo / ".gitignore").write_text("artifact\ncache/\nwhite*\n.env\n")
        self.git("add", ".gitignore", cwd=repo)
        self.git("commit", "--quiet", "-m", "fixture", cwd=repo)
        return repo

    def scan(self):
        output = io.BytesIO()
        helper.scan(os.fsencode(self.repos), GIT, output)
        self.manifest.write_bytes(output.getvalue())
        return output.getvalue()

    def encode(self, data=None):
        if data is not None:
            self.manifest.write_bytes(data)
        helper.encode(os.fsencode(self.repos), self.manifest, self.excludes)
        return self.excludes.read_text()

    def record(self, repo, relative):
        return os.fsencode(repo) + b"\0" + relative + b"\0"

    def test_fsmonitor_disabled_and_worktree_forced(self):
        repo = self.repo()
        marker = self.root / "hook-executed"
        hook = self.root / "hook"
        hook.write_text(f"#!{sys.executable}\nopen({str(marker)!r}, 'w').close()\n")
        hook.chmod(0o700)
        other = self.root / "other-worktree"
        other.mkdir()
        self.git("config", "core.fsmonitor", str(hook), cwd=repo)
        self.git("config", "core.worktree", str(other), cwd=repo)
        (repo / "artifact").write_text("ignored")
        self.assertIn(self.record(repo, b"artifact"), self.scan())
        self.assertFalse(marker.exists())

    def test_tracked_files_survive_ignore_rules(self):
        repo = self.repo()
        (repo / "cache").mkdir()
        (repo / "cache/keep").write_text("tracked")
        self.git("add", "--force", "cache/keep", cwd=repo)
        (repo / "cache/artifact").write_text("ignored")
        data = self.scan()
        self.assertIn(self.record(repo, b"cache/artifact"), data)
        self.assertNotIn(self.record(repo, b"cache/"), data)
        self.assertNotIn(b"cache/keep\0", data)

    def test_linked_worktree(self):
        repo = self.repo()
        worktree = self.repos / "worktree"
        self.git("worktree", "add", "--quiet", "-b", "fixture", str(worktree), cwd=repo)
        (worktree / "artifact").write_text("ignored")
        self.assertTrue((worktree / ".git").is_file())
        self.assertIn(self.record(worktree, b"artifact"), self.scan())

    def test_submodule(self):
        repo = self.repo()
        source = self.repo("submodule-source")
        self.git("-c", "protocol.file.allow=always", "submodule", "add", "--quiet",
                 str(source), "module", cwd=repo)
        module = repo / "module"
        (module / "artifact").write_text("ignored")
        self.assertTrue((module / ".git").is_file())
        self.assertIn(self.record(module, b"artifact"), self.scan())

    def test_directory_symlink_not_followed(self):
        outside = self.root / "outside"
        outside.mkdir()
        (outside / ".git").mkdir()
        (self.repos / "link").symlink_to(outside, target_is_directory=True)
        self.assertEqual(self.scan(), b"")

    def test_invalid_repository_fails(self):
        (self.repos / ".git").mkdir()
        with self.assertRaises(subprocess.CalledProcessError):
            self.scan()

    def test_unrepresentable_names_are_retained(self):
        data = self.record(self.repos, b"line\nbreak")
        data += self.record(self.repos, b"invalid-\xff")
        with contextlib.redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(self.encode(data), "")
        self.assertEqual(errors.getvalue().count("Keeping path"), 2)

    def test_invalid_records_cannot_replace_manifest(self):
        cases = [
            self.record(self.repos, b"../outside"),
            self.record(self.repos, b"/absolute"),
            self.record(self.repos, b".git/config"),
            self.record(self.repos, b"nested/.git"),
            self.record(self.repos / "project/.git", b"index"),
            self.record(self.repos, b"./artifact"),
            self.record(self.root / "repos-sibling", b"artifact"),
            self.record(self.repos, b""),
            b"unpaired\0",
            b"unterminated",
        ]
        for data in cases:
            with self.subTest(data=data):
                self.excludes.write_text("previous-complete-file")
                with self.assertRaises(ValueError):
                    self.encode(data)
                self.assertEqual(self.excludes.read_text(), "previous-complete-file")

    def test_symlink_and_fifo_manifests_rejected(self):
        other = self.root / "other"
        other.write_bytes(b"")
        self.manifest.symlink_to(other)
        with self.assertRaises(OSError):
            self.encode()
        self.manifest.unlink()
        os.mkfifo(self.manifest)
        with self.assertRaises(ValueError):
            self.encode()

    def test_manifest_size_bounded(self):
        with patch.object(helper, "MAX_BYTES", 4):
            with self.assertRaises(ValueError):
                self.encode(b"12345")

    @unittest.skipUnless(RESTIC, "RESTIC binary is required")
    def test_real_restic_backup(self):
        ignored = []
        for name in ["repo[ab]", "repo$HOME", "repo*", "repo?", "repo\\name", "repo "]:
            repo = self.repo(name)
            path = repo / "artifact"
            path.write_text("ignored")
            ignored.append(path)
        valuable_repo = self.repo("repoa")
        valuable = valuable_repo / "artifact"
        valuable.write_text("tracked valuable file")
        self.git("add", "--force", "artifact", cwd=valuable_repo)
        whitespace = valuable_repo / "white "
        whitespace.write_text("ignored")
        ignored.append(whitespace)
        unusual_repo = self.repo("line\nbreak")
        retained = unusual_repo / "artifact"
        retained.write_text("retained because its exclusion cannot be encoded")
        self.scan()
        with contextlib.redirect_stderr(io.StringIO()):
            self.encode()
        env = self.env | {
            "RESTIC_REPOSITORY": str(self.root / "backup"),
            "RESTIC_PASSWORD": "disposable-fixture-password",
            "RESTIC_CACHE_DIR": str(self.root / "cache"),
        }

        def restic(*args):
            return subprocess.run([RESTIC, *args], env=env, capture_output=True,
                                  check=True, timeout=30).stdout

        restic("init", "--quiet")
        restic("backup", "--quiet", "--exclude-file", str(self.excludes), str(self.repos))
        nodes = [json.loads(line) for line in restic("ls", "--json", "latest").splitlines()]
        paths = {node["path"] for node in nodes if node.get("struct_type") == "node"}
        self.assertIn(str(valuable), paths)
        self.assertIn(str(retained), paths)
        self.assertIn(str(valuable_repo / ".git/index"), paths)
        for path in ignored:
            self.assertNotIn(str(path), paths)


if __name__ == "__main__":
    unittest.main()
