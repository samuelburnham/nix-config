# worktrunk — git worktree switcher whose commit generation shells out to
# `claude` (see claude.nix). Kept out of base.nix so it's imported per profile
# rather than baked into every closure. Imported alongside claude.nix by the
# bare-metal workstations (desktop.nix, laptop.nix) and the isolated
# environments (dev-vm.nix, the Ubuntu box).
{
  config,
  pkgs-unstable,
  lib,
  ...
}:
{
  options.programs.worktrunk.autoAllowDirenv = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Automatically approve .envrc files in newly created worktrees.";
  };

  config.home.packages = [ pkgs-unstable.worktrunk ];

  config.programs.bash.initExtra = ''
    eval "$(${lib.getExe pkgs-unstable.worktrunk} config shell init bash)"
  '';

  # worktrunk — `wt switch --create <branch>` spins up a new worktree as a
  # sibling dir (default template) and fires this pre-start hook, which
  # creates a dedicated tmux session for it and drops the current client
  # into it. `wt remove` / `wt merge` reverse the whole thing.
  config.home.file.".config/worktrunk/config.toml".text = ''
    # Worktrunk shell-escapes hook variables; leave them unquoted.

    # Array-of-tables keeps pre-start steps serial: session creation
    # completes before any optional direnv approval.
    [[pre-start]]
    tmux = """
    # sesh supplies git-aware session naming, zoxide registration, and
    # any configured startup command. It switches the client when $TMUX
    # is set and attaches otherwise.
    sesh connect {{ worktree_path }}
    """

    ${lib.optionalString config.programs.worktrunk.autoAllowDirenv ''
      [[pre-start]]
      # Guarded on .envrc presence so worktrees in non-direnv repos don't
      # error. `direnv allow` accepts a path and resolves the .envrc itself.
      direnv = """
      [ -f {{ worktree_path }}/.envrc ] && direnv allow {{ worktree_path }} || true
      """
    ''}

    # A pre-remove kill-session can SIGHUP wt before it spawns the
    # detached file deletion, leaving the directory in .git/wt/trash.
    # post-remove runs detached after removal has been started, so
    # closing the session cannot interrupt that handoff.
    [post-remove]
    tmux = """
    # sesh records the worktree as session_path, which survives renaming
    # the session and removing the directory. Session names can change.
    tmux list-sessions -F '#{session_id} #{session_path}' 2>/dev/null |
      while read -r session path; do
        if [ "$path" = {{ worktree_path }} ]; then
          tmux kill-session -t "$session"
        fi
      done
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
