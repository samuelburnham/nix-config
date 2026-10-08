# ubuntu — standalone home-manager config for a stock Ubuntu AMI with
# Nix installed (see terraform-server for provisioning). No NixOS, no
# GUI, no rebuild wrapper.
{
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    ../modules/base.nix
    ../modules/claude.nix
    ../modules/codex.nix
    ../modules/worktrunk.nix
  ];

  # This config runs on a disposable cloud VM, so default to "auto" mode like
  # the dev microvm — Claude auto-approves safe actions and blocks risky ones
  # (see dev-vm.nix). Overrides base.nix's prompting default.
  programs.claude-code.settings.permissions.defaultMode = "auto";

  # The bench box installs the home-manager-setup helper into ~/.local/bin.
  # Ubuntu's stock ~/.profile put that directory on PATH, but activation
  # replaces that file, so keep it on PATH here or the helper cannot be
  # re-run by name to pull updates.
  home.sessionPath = [ "$HOME/.local/bin" ];

  # Only SSH login shells own a tmux client; the generated bashrc already
  # returns before this for non-interactive shells. Keep the login shell
  # alive so detaching returns to it without immediately reattaching.
  programs.bash.initExtra = lib.mkAfter ''
    if [[ -n ''${SSH_TTY:-} && -z ''${TMUX:-} ]] && shopt -q login_shell; then
      tmux-resume
    fi
  '';

  home.packages = [
    inputs.self.packages.${pkgs.system}.nvim
  ];

  # Ghostty's terminfo (`xterm-ghostty`) isn't in Ubuntu's ncurses database,
  # so without it every curses program on the box sees an unknown $TERM and
  # degrades — wrong colours, broken drawing. Only the terminfo output is
  # needed, not the terminal itself. Installed into ~/.terminfo, which
  # ncurses searches unconditionally, rather than relying on TERMINFO_DIRS
  # being exported into every session.
  home.file = {
    ".terminfo/x/xterm-ghostty".source = "${pkgs.ghostty.terminfo}/share/terminfo/x/xterm-ghostty";
    ".terminfo/g/ghostty".source = "${pkgs.ghostty.terminfo}/share/terminfo/g/ghostty";
  };
}
