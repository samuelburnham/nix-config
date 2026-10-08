# Claude Code — the self-pinned release plus its settings.json, CLAUDE.md,
# sandbox, permissions, and hooks. Kept OUT of base.nix and imported only
# where it's wanted, so it isn't in every closure by default:
#   - the disposable/isolated environments — the dev microvm (dev-vm.nix)
#     and the Ubuntu cloud box (ubuntu.nix) — which default to "auto" mode;
#   - the bare-metal workstations (desktop.nix, laptop.nix), where claude
#     runs directly against real repos — and, on the desktop, debugs the
#     host-side Hyprland/waybar setup the dev VM can't see.
# The workstations are the hosts with the real ~/.config, /run/secrets, and
# host services in reach, so they deliberately keep the prompting
# `defaultMode` and the bubblewrap `sandbox` below — claude can't act
# unattended there.
{
  inputs,
  pkgs-master,
  lib,
  config,
  ...
}:
let
  # Tool-agnostic half of the context below; codex.nix appends to the same
  # string, so shared rules are stated once instead of in each agent's copy.
  sharedContext = import ./agent-context.nix;

  rustfmtHook = ''
    f=$(jq -r '.tool_input.file_path')
    if [ -z "$f" ] || [ "$f" = "null" ]; then exit 0; fi
    d=$(dirname "$f")
    while [ "$d" != / ] && [ ! -f "$d/.envrc" ]; do d=$(dirname "$d"); done
    # direnv runs rustfmt from the repo's devshell (pinned toolchain). It is
    # intentionally absent on the microvm host (see desktop.nix), so fall back
    # to a plain rustfmt when direnv isn't on PATH.
    if [ -f "$d/.envrc" ] && command -v direnv >/dev/null 2>&1; then
      direnv exec "$d" rustfmt "$f"
    else
      rustfmt "$f"
    fi
  '';

  # Notification hook: replaces Claude's generic "waiting for input" desktop
  # notification with one that names the worktree/session it came from, so a
  # notification from a backgrounded session is identifiable. The built-in
  # channel is turned off (preferredNotifChannel below) to avoid a duplicate;
  # this hook fires regardless of that setting.
  #
  # Delivery is OSC 9 written to the controlling terminal — the same sequence
  # Ghostty already turns into a system notification (see base.nix
  # allow-passthrough). That crosses tmux and the VM→host ssh boundary
  # unchanged, so it works with or without either; inside tmux the sequence is
  # wrapped for passthrough (leading ESC doubled) or tmux swallows it. Writing
  # to /dev/tty keeps it out of the hook's stdout, which Claude parses.
  notifyHook = ''
    input=$(cat)

    name=""
    if [ -n "''${TMUX:-}" ]; then
      # Already looking at this pane (active pane of the current window on an
      # attached client)? Then a desktop notification is just noise — skip it.
      if [ "$(tmux display-message -p -t "''${TMUX_PANE:-}" \
              '#{session_attached}#{window_active}#{pane_active}' 2>/dev/null)" = "111" ]; then
        exit 0
      fi
      name=$(tmux display-message -p -t "''${TMUX_PANE:-}" '#S' 2>/dev/null || true)
    fi
    if [ -z "$name" ]; then
      cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
      [ -z "$cwd" ] && cwd="$PWD"
      top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)
      name=$(basename "''${top:-$cwd}")
    fi

    msg=$(printf '%s' "$input" | jq -r '.message // "is waiting for your input"' 2>/dev/null)
    body="$name — $msg"

    if [ -n "''${TMUX:-}" ]; then
      printf '\033Ptmux;\033\033]9;%s\a\033\\' "$body" > /dev/tty 2>/dev/null || true
    else
      printf '\033]9;%s\a' "$body" > /dev/tty 2>/dev/null || true
    fi
  '';
in
{
  # settings.json + CLAUDE.md. home-manager writes settings.json to
  # ~/.claude/settings.json in each environment that imports this module; that
  # ~/.claude is the environment's own state (the dev VM's lives on its private
  # home volume), independent of every other.
  programs.claude-code = {
    enable = true;
    # nixpkgs-master's update bot lands each upstream release within about a
    # day, and master is consumed directly, so there is no channel-advance delay
    # on top of that. Reach for an `overrideAttrs` setting `version` + `src`
    # only to jump ahead of a bot run for a specific fix, or to hold back a
    # release that breaks something; a standing pin drifts further behind than
    # the lag it was meant to avoid.
    #
    # Routed through `package` rather than home.packages because `lspServers`
    # below only takes effect when the module can wrap the binary: it builds a
    # symlinkJoin launcher that injects `--plugin-dir` (carrying the generated
    # .lsp.json) and refuses a null package. The module adds that wrapper to
    # home.packages itself, so it must not also be listed there by hand.
    package = pkgs-master.claude-code;
    settings = {
      theme = "dark";
      # By default a session instruction asks for a Co-Authored-By trailer, a
      # PR footer, and a session URL -- contradicting the CLAUDE.md rule
      # below, and winning, since it arrives later and claims to supersede
      # it. Empty strings hide the trailer and footer; `includeCoAuthoredBy`
      # is the deprecated predecessor of this object and never covered the
      # session URL.
      attribution = {
        commit = "";
        pr = "";
        sessionUrl = false;
      };
      # Default model for every new session. `/model` still switches within a
      # session, and CLAUDE_CODE_MODEL / --model override this at launch.
      model = "claude-fable-5-1";
      # Suppress Claude's own generic desktop notification; the Notification
      # hook below emits a replacement that names the originating
      # worktree/session. The hook fires independent of this channel setting.
      preferredNotifChannel = "notifications_disabled";
      # Background/fleet-view sessions edit the checkout in place instead of
      # spinning up their own git worktree. Worktrees here are made by hand,
      # one Claude per worktree with a couple of agents inside it; the
      # auto-isolation would otherwise nest a second, wrongly-based worktree.
      worktree.bgIsolation = "none";
      # Don't auto-fetch the claude.ai account connectors (Gmail, Calendar,
      # Drive, ...) into the CLI. They're attached to the claude.ai account,
      # not configured here, and surface as an unauthenticated-MCP-server
      # warning every session. Off keeps the CLI to locally-declared MCP
      # servers only; the connectors stay available in the claude.ai web app.
      disableClaudeAiConnectors = true;
      # Opt out of non-essential network calls individually rather than via the
      # CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC umbrella — and crucially NOT via
      # DISABLE_TELEMETRY. Both put claude into "restricted traffic" mode (the
      # internal Yns() returns non-"default"), which short-circuits GrowthBook
      # feature-flag evaluation. The `allow_remote_control` gate then never
      # resolves true, so the /remote-control command is never registered (the
      # same path also gates 1M context and Agent View). Telemetry and flag
      # delivery share one upstream code path, so there is no config-only way to
      # suppress telemetry while keeping flags live — keeping it off means losing
      # Remote Control. We therefore disable only the things on independent
      # paths: error reporting and the feedback command. The autoupdater stays
      # off because claude is nix-pinned and must not self-update out from under
      # home-manager (the nixpkgs wrapper already sets this too).
      env = {
        DISABLE_ERROR_REPORTING = "1";
        DISABLE_AUTOUPDATER = "1";
        DISABLE_FEEDBACK_COMMAND = "1";
        # The periodic "was this helpful?" popup is a separate survey from the
        # /feedback command above. Its show-check honours this var before the
        # allow_product_feedback flag, so it's a clean off switch — no bearing
        # on the flag/Remote-Control tradeoff described above.
        CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
      };
      sandbox = {
        enabled = true;
        autoAllowBashIfSandboxed = true;
        allowUnsandboxedCommands = true;
        # cargo's caches all live under ~/.cargo: the registry index/src, git
        # checkouts (git/db, git/checkouts), and the .package-cache lock.
        # Without an explicit allowWrite the sandbox keeps the real ~/.cargo
        # read-only and redirects home writes to a shadow tree, so cargo can't
        # populate or update its cache — fetching a git dependency fails with
        # EROFS on ~/.cargo/git/db. Listing it here writes through to the real
        # cache, which also keeps it persistent and shared across runs instead
        # of rebuilt into a throwaway shadow each time.
        filesystem.allowWrite = [ "${config.home.homeDirectory}/.cargo" ];
        network.allowedDomains = [
          "github.com"
          "api.github.com"
          "index.crates.io"
        ];
      };
      permissions = {
        # Prompt before applying Edit/Write/MultiEdit by default. mkDefault so
        # the disposable/isolated VMs (dev microvm, Ubuntu cloud box) override
        # with a plain "auto" (see dev-vm.nix / ubuntu.nix); the persistent
        # workstations keep this prompting default. Any mode can still be
        # toggled by hand (Shift+Tab) for a session, and Bash and other tools
        # pass the allow-list and inner sandbox regardless of mode.
        defaultMode = lib.mkDefault "default";
        allow = [
          "Read(${config.home.homeDirectory}/repos/**)"
          "Grep(${config.home.homeDirectory}/repos/**)"
          "Edit(${config.home.homeDirectory}/repos/**)"
          "Read(${config.home.homeDirectory}/.cargo/**)"
          "Grep(${config.home.homeDirectory}/.cargo/**)"
          "Edit(${config.home.homeDirectory}/.cargo/**)"
          "Read(/nix/store/**)"
          "Grep(/nix/store/**)"
          "Bash(cargo build:*)"
          "Bash(cargo check:*)"
          "Bash(cargo run:*)"
          "Bash(cargo test:*)"
          "Bash(cargo fmt:*)"
          "Bash(cargo clippy:*)"
          "Bash(cargo xclippy:*)"
          "Bash(lake build:*)"
          "Bash(lake exe:*)"
          "Bash(lake test:*)"
          "Bash(nix develop:*)"
          "Bash(nix build:*)"
          "Bash(nix fmt:*)"
          "Bash(nix flake show:*)"
          "Bash(nix flake metadata:*)"
          "Bash(nix eval:*)"
          "Bash(grep:*)"
          "Bash(rg:*)"
          "Bash(fd:*)"
          "Bash(jq:*)"
          "Bash(tail:*)"
          "Bash(head:*)"
          "Bash(wc:*)"
          "Bash(git status:*)"
          "Bash(git log:*)"
          "Bash(git diff:*)"
          "Bash(git show:*)"
          "Bash(git branch:*)"
          "Bash(git remote -v:*)"
          "Bash(git check-ignore:*)"
          "Bash(cargo bench:*)"
          "Bash(ls:*)"
          "Bash(xxd:*)"
          "WebFetch(domain:github.com)"
          "WebFetch(domain:api.github.com)"
          "WebFetch(domain:index.crates.io)"
          "Read(/tmp/**)"
          "Grep(/tmp/**)"
        ];
        # Human-only actions (destroying/applying infra, driving cloud CLIs).
        # The authoritative, tamper-proof copy is the root-owned
        # managed-settings.json (common/claude-managed-settings.nix); this
        # user-level copy is a best-effort fallback for hosts that don't
        # deploy the managed file (the standalone Ubuntu box) and shares the
        # same source list so the two can't drift.
        deny = import ../../common/claude-deny-list.nix;
      };
      hooks = {
        # tmux-assistant-resurrect session tracking. SessionStart writes a state
        # file keyed by this claude process's PID (session id + cwd + model),
        # which tmux-resurrect's post-save hook reads to record what each pane
        # was running; SessionEnd removes it. Keying by PID is what lets two
        # conversations in the same directory be resumed into their own panes.
        # See base.nix for the matching resurrect save/restore hooks.
        SessionStart = [
          {
            matcher = "";
            hooks = [
              {
                type = "command";
                command = "bash '${inputs.tmux-assistant-resurrect}/hooks/claude-session-track.sh'";
              }
            ];
          }
        ];
        SessionEnd = [
          {
            matcher = "";
            hooks = [
              {
                type = "command";
                command = "bash '${inputs.tmux-assistant-resurrect}/hooks/claude-session-cleanup.sh'";
              }
            ];
          }
        ];
        Notification = [
          {
            matcher = "";
            hooks = [
              {
                type = "command";
                command = notifyHook;
              }
            ];
          }
        ];
        PostToolUse = [
          {
            matcher = "Edit|Write|MultiEdit";
            hooks = [
              {
                type = "command";
                "if" = "Edit(**/*.rs)";
                command = rustfmtHook;
              }
              {
                type = "command";
                "if" = "Write(**/*.rs)";
                command = rustfmtHook;
              }
              {
                type = "command";
                "if" = "MultiEdit(**/*.rs)";
                command = rustfmtHook;
              }
            ];
          }
        ];
      };
    };
    # rust-analyzer for `.rs` files, giving claude LSP diagnostics and code
    # intelligence. The module serializes this to a .lsp.json inside the
    # `--plugin-dir` it wraps the binary with (see `package` above) — there is
    # no settings.json key for it, so it lives here rather than under `settings`.
    #
    # `command` is a bare name resolved from PATH at spawn — NOT via `direnv
    # exec` like the rustfmt hook above — so the server only starts when claude
    # is launched from a direnv-activated devshell that provides rust-analyzer.
    # We deliberately don't install it globally; on hosts/repos without it on
    # PATH the spawn just fails and is skipped, rather than erroring the session.
    lspServers = {
      rust-analyzer = {
        command = "rust-analyzer";
        extensionToLanguage = {
          ".rs" = "rust";
        };
      };
    };
    context = sharedContext + ''

      # Commit attribution

      Never add a `Co-Authored-By: Claude ...` trailer — or any Claude/Anthropic
      co-author or attribution line — to git commits or PR descriptions.

      # Claude config location

      Never create or write to a `.claude/` directory inside a repository — no
      project-scoped `settings.json`, hooks, skills, agents, commands, or memory
      under a repo. Put all Claude configuration in the global `~/.claude/`
      instead. This applies to everything, including tools/skills that default to
      writing project config (e.g. permission allowlists, hooks): target
      `~/.claude/` or ask, never the repo. If a task seems to require repo-local
      `.claude/` config, stop and confirm first.

      # nix-config branch

      `main` is the only live branch of `~/repos/nix-config`: commit there, and
      point anything that pulls the flake (`github:samuelburnham/nix-config/...`)
      at `main`. The `nixos` branch is a stale ancestor, not a target.

      # Memory

      Record durable facts, preferences, and operational lessons as edits to
      THIS file (`~/repos/nix-config/home/modules/claude.nix`) — add a short
      topical section below. A lesson that applies to any coding agent, not just
      Claude, goes in `agent-context.nix` instead, which this file appends to.
      Do NOT write them to `~/.claude/projects/*/memory/`: that path is
      home-manager-managed or ephemeral VM state and is not version-controlled,
      so it is lost on reprovision. Edits here need a `home-manager switch` to
      take effect. Keep entries terse — everything here loads into every
      session's context.

      # Temp files outside the sandbox

      `$TMPDIR` is set only inside the Bash sandbox. A command run with the
      sandbox disabled sees it unset, so `$TMPDIR/x` becomes `/x` and fails
      with permission denied; use `mktemp -d` or the session scratchpad path
      there instead.

      # Build logic ownership

      Nix-only build logic stays in `flake.nix`. Never change a repo's native
      build files (`lakefile.lean`, `Cargo.toml`, build scripts) to make the
      Nix packaging simpler or faster; patch or wrap them from the flake
      instead, as ix's flake already does with `postPatch`.
    '';
  };

  # On resume, Claude offers to restart from a summary instead of the full
  # transcript ("This session is 3h old and 120k tokens"). It only asks when the
  # session is both older than CLAUDE_CODE_RESUME_THRESHOLD_MINUTES (70) and
  # bigger than CLAUDE_CODE_RESUME_TOKEN_THRESHOLD, whose 100k default is far
  # too eager against a 1M context — raised here so the offer only shows up for
  # sessions actually approaching the limit.
  # The dialog's own "Don't ask me again" only sets resumeReturnDismissed in
  # ~/.claude.json, which Claude owns and rewrites, so it can't be declared here.
  # This must be a real environment variable: values in the settings.json `env`
  # block are filtered against a fixed allowlist that omits this one.
  home.sessionVariables.CLAUDE_CODE_RESUME_TOKEN_THRESHOLD = "600000";

  # Claude Code treats ~/.claude/settings.json as its own mutable runtime
  # config and periodically rewrites it — replacing the read-only store
  # symlink installed above with a plain file (observed reset to `{}`).
  # Without force, the next activation sees a non-symlink in the way and
  # tries to back it up; with backupFileExtension set that backup collides
  # with a prior switch's leftover .bak and aborts the whole home-manager
  # activation. force makes home-manager overwrite the stray file in place,
  # re-asserting the managed settings on every switch with no backup step,
  # so a runtime rewrite can never wedge a rebuild.
  # Keyed to the module's own configDir (absolute, ~/.claude by default) so
  # this merges into the module's home.file entry rather than colliding with
  # it as a second entry pointing at the same target.
  home.file."${config.programs.claude-code.configDir}/settings.json".force = true;
}
