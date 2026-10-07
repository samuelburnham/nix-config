# worktrunk — git worktree switcher whose commit generation shells out to
# `claude` (see claude.nix). Kept out of base.nix so it's imported per profile
# rather than baked into every closure. Imported alongside claude.nix by the
# bare-metal workstations (desktop.nix, laptop.nix) and the isolated
# environments (dev-vm.nix, the Ubuntu box).
{
  inputs,
  ...
}:
{
  imports = [
    inputs.worktrunk.homeModules.default
  ];

  # worktrunk — upstream's home-manager module installs the package and
  # wires `eval "$(wt config shell init bash)"` into bash.initExtra. Hooks
  # and aliases still live in ~/.config/worktrunk/config.toml below.
  programs.worktrunk = {
    enable = true;
    enableBashIntegration = true;
  };

  # worktrunk — `wt switch --create <branch>` spins up a new worktree as a
  # sibling dir (default template) and fires this pre-start hook, which
  # creates a dedicated tmux session for it and drops the current client
  # into it. `wt remove` / `wt merge` reverse the whole thing.
  home.file.".config/worktrunk/config.toml".text = ''
    # Worktrunk shell-escapes hook variables; leave them unquoted.

    # Array-of-tables (`[[pre-start]]`) runs steps serially, in order.
    # worktrunk deprecated the named-key table form (`[pre-start]` with
    # `tmux`/`direnv` keys) — it warns on every `wt` invocation and will
    # flip that form's execution from serial to parallel. `[[pre-start]]`
    # blocks pin the serial ordering: create the session first, then
    # direnv-allow the worktree it lives in.
    [[pre-start]]
    tmux = """
    # Delegate session creation to sesh (base.nix) rather than a raw
    # `tmux new-session`, so worktree sessions get the same treatment as
    # every other session here: sesh's git-aware namer (which maps `.`
    # and `:` to `_`, so a `nix-config.test` worktree becomes the
    # tmux-safe `nix-config_test`), zoxide registration, and any
    # configured startup command. sesh switches the client when $TMUX is
    # set and attaches otherwise, so no explicit switch-client is needed.
    sesh connect {{ worktree_path }}
    """

    [[pre-start]]
    # Guarded on .envrc presence so worktrees in non-direnv repos don't
    # error. `direnv allow` accepts a path and resolves the .envrc itself.
    direnv = """
    [ -f {{ worktree_path }}/.envrc ] && direnv allow {{ worktree_path }} || true
    """

    # Session teardown runs post-remove, not pre-remove: `wt remove`'s
    # default background path renames the worktree into `.git/wt/trash/`,
    # prunes metadata and deletes the branch synchronously, then spawns a
    # detached `rm -rf` to delete the files. A pre-remove `kill-session`
    # tears down the very session `wt remove` runs in, SIGHUPing `wt`
    # after the prune but before it spawns that `rm` — so the branch and
    # session vanish while the directory survives in trash. post-remove
    # hooks run detached after the `rm` is already spawned, so the delete
    # completes first and the session dies last.
    [post-remove]
    tmux = """
    # Must match the name sesh generated in pre-start: its default namer
    # is the basename with `.` and `:` mapped to `_`.
    S=$(basename {{ worktree_path }} | tr '.:' '_')
    tmux kill-session -t "=$S" 2>/dev/null || true
    """

    # Short aliases. Aliases run as shell commands (not as wt subcommand
    # names), so the `wt` prefix is explicit. `{{ args }}` forwards
    # positional args verbatim with shell-safe escaping.
    #
    # `--no-cd` on the two switch variants suppresses worktrunk's shell-cd
    # directive: the pre-start tmux hook already lands us in a session
    # whose cwd is the new worktree, so sourcing a `cd` in the *original*
    # shell would only drag the session we just left into the new dir —
    # surprising when we swap back to it later. Leaving the flag off the
    # plain `wt switch` / `wt switch --create` commands means the rare
    # out-of-tmux invocation still gets shell-follow behavior by default.
    [aliases]
    s = "wt switch --no-cd {{ args }}"
    c = "wt switch --create --no-cd {{ args }}"
    m = "wt merge {{ args }}"
    r = "wt remove {{ args }}"
    l = "wt list {{ args }}"

    # Sonnet over upstream's haiku default: commits are load-bearing
    # history and branch diffs can run thousands of lines, where
    # haiku's summarization drops important context. The rest of the
    # flags strip Claude Code's normal scaffolding (skills, CLAUDE.md,
    # tool loop, session write) so this behaves like a one-shot API
    # call rather than an interactive agent run.
    [commit.generation]
    command = "CLAUDECODE= MAX_THINKING_TOKENS=0 claude -p --no-session-persistence --model=sonnet --tools=''' --disable-slash-commands --setting-sources=''' --system-prompt='''"
  '';
}
