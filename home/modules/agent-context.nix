# Prose shared by every coding agent's global context file — claude.nix's
# `context` (~/.claude/CLAUDE.md) and codex.nix's (~/.codex/AGENTS.md).
# Evaluates to a plain string that each module concatenates its own
# tool-specific sections onto, so a rule that applies to any agent is stated
# once rather than drifting between copies.
#
# Tool-agnostic rules only. Anything naming a particular agent's config paths,
# state directories, or attribution format belongs in that agent's module.
''
  # Research clones

  `~/repos/clones/` contains third-party source trees cloned for read-only
  research and context — not for editing. Use them to inspect upstream
  implementations, cross-reference APIs, and answer "how does X actually
  work" questions instead of guessing from training data.

  Sorted by topic. New clones land in the matching topic dir.

  Rules:
  - Read-only. Don't edit, commit, or push here. If you need to modify
    upstream code, fork into `~/repos/forks/` instead.
  - Check here before WebFetching a repo's docs or source — the local
    clone is authoritative for whatever commit it's pinned to.
  - Before browsing a clone, bring it to the latest upstream default
    branch — never answer from a stale tree. Small repos: `git fetch
    origin <default>` (no `--tags`) and reset. Huge repos (lean4,
    nixpkgs): shallow-fetch the tip only — `git fetch --depth 1 origin
    <default> && git checkout --detach FETCH_HEAD` — which gives the
    full latest tree for grepping without the history transfer. For a
    single known file, `gh api repos/<owner>/<repo>/contents/<path>`
    is cheaper still. Never run unbounded full fetches of huge repos.

  # Comments and docstrings

  Comments and docstrings explain the code, not the author's process.
  Never write a comment whose subject is you or this session — what you
  did, why you changed it, what it replaces, what task it came from, or
  which caller prompted it. That belongs in the commit message or PR
  description and rots the moment the code moves.

  A comment is only worth writing if a future reader — with no knowledge
  of this conversation — would benefit from it. It should explain:
  - *what* the code does, only when the code itself isn't self-evident
    (rare — prefer better names first); or
  - *why* the code is the way it is: a non-obvious constraint, a subtle
    invariant, a workaround for a specific upstream bug, behavior that
    would otherwise surprise a reader.

  Concretely, never write:
  - "Added X to fix Y", "Replaced the old Z", "Refactored from ..."
  - "Used by the foo flow", "Called from bar.ts", "Handles the case
    from issue #123"
  - Restatements of the code ("increment i by 1", "return the result")
  - TODOs referencing the current task ("TODO: wire this up once the
    other PR lands") — track those in the PR, not the source.

  This applies to every language's comment/docstring syntax (`//`, `#`,
  `/** */`, `"""..."""`, `---`, `;;`, etc.) and to commit messages for
  code *inside* diffs (the commit body itself is the right place for
  process narrative; the code is not).

  # Git pushing

  Never run `git push`, or otherwise push to a remote. Commit locally when
  asked, but pushing is always the user's action: when a push is the next
  step, give the user the exact command to run instead of running it.

  # Rust dependency updates

  Never run a blanket `cargo update` in a Rust repository. It can update
  hundreds or thousands of dependencies that must instead be audited through
  focused Dependabot PRs for supply-chain security. When a dependency needs to
  be updated, use `cargo update -p <dep>` to scope the lockfile update.

  # Nix store safety

  Never run `du` — or any recursive file walk (`find`, `ls -R`, `wc` over a
  tree) — over the Nix store or other multi-hundred-GB trees. On this host
  the store is a large shared volume, so it means millions of `stat()` calls
  (sustained CPU + I/O) and can run for hours; one such `du` had to be killed
  by restarting the microVM. For free space use `df -h <path>`; for a
  specific store path's size use `nix path-info -Sh <path>`. If a heavy
  command gets backgrounded, verify its PID is actually dead — don't trust a
  `pkill` that can itself be timed out.

  # Long-running builds and benchmarks

  Ask before starting work that will occupy the machine for a long time:
  whole-project builds, cold `cargo`/`nix` builds, full test suites,
  benchmark sweeps. Wanting to verify a change is not authorization to spend
  the user's time — build the narrowest target that actually tests the claim,
  say what it will cost before starting, and get agreement before anything
  broader. Backgrounding does not make it cheaper, it only hides it.

  The gate is permission, never throttling. Once work is asked for, run it at
  the machine's full width: leave `-j`/`--jobs`, `--test-threads`,
  `RAYON_NUM_THREADS` and friends at their defaults. Never quietly cap
  parallelism to be polite — it makes the work take longer for no benefit,
  and on a benchmark it silently invalidates the numbers. The dev VM is given
  all 24 logical CPUs deliberately, and CPUWeight on the microvm@dev unit
  already lets host UI processes outbid VM threads, so throttling by hand
  buys nothing the system isn't handling.
''
