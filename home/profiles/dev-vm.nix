# Home-manager entry point for the dev microvm. The VM runs the
# interactive dev environment — tmux, nvim, claude, shell, builds — which
# you reach by ssh from the host's ghostty. No compositor or terminal-
# emulator config here (those live on the host); the VM only runs a shell.
{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # Switch every local nvim's catppuccin flavour. Called by the
  # client-{dark,light}-theme tmux hooks below (which fire from the
  # terminal's in-band OSC 2031 light/dark reports), with $1 = the nvim
  # user command (DarkMode / LightMode).
  nvimThemeRelay = pkgs.writeShellScript "nvim-theme-relay" ''
    for sock in "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/nvim.*.0; do
      [ -S "$sock" ] || continue
      ${inputs.self.packages.${pkgs.system}.nvim}/bin/nvim \
        --server "$sock" --remote-send "<Cmd>$1<CR>" 2>/dev/null &
    done
    true
  '';
in
{
  imports = [
    ../modules/base.nix
    ../modules/alias.nix
    ../modules/claude.nix
    ../modules/codex.nix
    ../modules/worktrunk.nix
  ];

  home.packages = [
    inputs.self.packages.${pkgs.system}.nvim
  ];

  # nvim can't read the terminal's CSI ?997 theme report itself (its
  # TermResponse only surfaces OSC/DCS), so tmux — which tracks the in-band
  # OSC 2031 light/dark state — relays changes to nvim. On this headless VM
  # auto-dark-mode's D-Bus probe finds no desktop portal, so these hooks are
  # nvim's only live theme signal; nvim seeds the initial flavour from
  # #{client_theme} on startup (see nvim.nix).
  programs.tmux.extraConfig = lib.mkAfter ''
    set-hook -g client-dark-theme  'run-shell -b "${nvimThemeRelay} DarkMode"'
    set-hook -g client-light-theme 'run-shell -b "${nvimThemeRelay} LightMode"'
  '';
  # The VM is a brand-new system with no prior HM state; override
  # base.nix's host-side 25.05 pin so it doesn't collide with the
  # microvm host module's 25.11 default.
  home.stateVersion = lib.mkForce "25.11";

  # No SSH agent in the VM. Private GitHub repos still clone with their
  # SSH-style URLs because git transparently rewrites git@github.com /
  # ssh://git@github.com fetches to HTTPS, which authenticate with the
  # forwarded read-only GH_TOKEN (gh credential helper, base.nix). You run
  # `git clone git@github.com:org/repo` unchanged; the rewrite is internal.
  # VM-only — the host keeps real SSH, so push (write, hardware key) works
  # there. Pushing from the VM is intentionally unsupported (read-only
  # token → 403); push from the host.
  programs.git.settings.url."https://github.com/".insteadOf = [
    "git@github.com:"
    "ssh://git@github.com/"
  ];

  # The dev microvm is the isolated sandbox this tooling is meant to run in,
  # so default to "auto" mode: Claude auto-approves actions it classifies as
  # safe and still blocks risky ones / suspected prompt injection. This plain
  # value overrides claude.nix's prompting default; the workstations keep it.
  programs.claude-code.settings.permissions.defaultMode = "auto";

  # `gh api` stays non-prompting here (it is kept out of the shared allow-list
  # in claude.nix): the token forwarded into the VM is the read-only PAT, so
  # `gh api` calls can query GitHub but not write it. Concatenates onto the
  # shared allow-list for the VM only.
  programs.claude-code.settings.permissions.allow = [ "Bash(gh api:*)" ];

  # Make cargo fetch git deps via the git CLI so private deps go through
  # the credential helper + token (and the rewrite above) rather than
  # cargo's built-in fetcher, which ignores them.
  home.sessionVariables.CARGO_NET_GIT_FETCH_WITH_CLI = "true";
}
