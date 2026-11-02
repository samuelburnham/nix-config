# Ghostty terminal config — the host-native terminal. Super+T opens it
# already ssh'd into the dev microvm and attached to tmux (ssh-dev-vm);
# plain ghostty is a host shell. Kept in its own file (imported by
# gui.nix) rather than inlined so the config is easy to find and reuse.
{ config, ... }:
{
  # TODO (Ghostty 1.4+, once available on nixpkgs unstable):
  # - Select unstable Ghostty (currently stable by default) and align VM/Ubuntu
  #   terminfo; refresh terraform-server's snapshot, keeping /etc/terminfo for nvtop.
  # - Consider +ssh in ssh-bench/ssh-dev-vm; opt-in shell integration does not
  #   wrap these scripts. Avoid auto-installing over HM's terminfo symlinks.
  # - Test cursor restoration through SSH/tmux/Neovim before removing the
  #   PROMPT_COMMAND bar-cursor workaround; 1.4 fixes terminfo's cursor reset.
  # - Review clipboard-read=allow: Kitty clipboard reads include images/HTML.
  # - Check Ctrl+Shift+Up/Down's new prompt-navigation bindings.
  # Highlights: compressed scrollback, faster resizing, notification
  # deduplication, and security fixes.
  # https://ghostty.org/docs/install/release-notes/1-4-0
  programs.ghostty = {
    enable = true;
    settings = {
      font-family = "FiraCode Nerd Font Mono";
      theme = "dark:Catppuccin Mocha,light:Catppuccin Latte";
      shell-integration-features = "no-cursor";
      cursor-style = "bar";
      mouse-hide-while-typing = true;
      working-directory = "${config.home.homeDirectory}/repos";
      keybind = [
        # CSI u keeps Shift+Enter distinct from Enter through tmux. A raw
        # newline is Ctrl+J, which tmux binds to pane navigation.
        "shift+enter=text:\\x1b[13;2u"
        # Ghostty's built-in default binds ctrl+enter to toggle_fullscreen,
        # which fires by accident during normal terminal use. Send a plain
        # carriage return instead so a stray ctrl+enter just submits the line.
        # (`unbind` would fall back to the keyboard protocol's ctrl+enter
        # encoding, which leaks as a literal `;5;13~` into the program.)
        "ctrl+enter=text:\\r"
      ];
      # OSC 52 clipboard reads without a per-request dialog. Default
      # "ask" silently fails when the dialog is dismissed before the
      # invoking command exits.
      clipboard-read = "allow";
    };
  };
}
