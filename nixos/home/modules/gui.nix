# Shared GUI overlay — common bits imported by both DE-specific overlays
# (./gnome.nix and ./hyprland.nix). Holds the desktop applications,
# kitty terminal, image-MIME defaults, Podman, Firefox profile, and the
# nvim package that behave the same regardless of which compositor is
# active. DE-specific packages (pop-shell, gnome-control-center, waybar,
# etc.) stay in their respective overlay.
#
# When both overlays are imported on the same host (desktop, where GNOME
# stays around as a fallback), this file is included twice — Nix's
# module system dedupes by path, so shared options only get defined once.
{
  pkgs,
  pkgs-unstable,
  pkgs-master,
  inputs,
  config,
  ...
}:
{
  imports = [
    ./firefox.nix
    # Ghostty as the host-native terminal. dev-vm.nix imports ghostty.nix
    # directly (not via this file), so the microvm guest keeps its own
    # copy; path-dedup means the host's two DE overlays share this one.
    ./ghostty.nix
  ];

  home.packages =
    with pkgs;
    [
      # Disabled: both channels currently pin bitwarden-desktop to EOL
      # electron_39, which nixpkgs refuses as insecure. The Firefox
      # extension covers day-to-day use (see the extension-popup window
      # rule in hyprland.nix). To re-enable once upstream re-pins to a
      # supported Electron, uncomment — and if it's still on an EOL
      # electron, add that version to permittedInsecurePackages on the
      # pkgs-unstable import in flake.nix.
      # pkgs-unstable.bitwarden-desktop
      vscode
      # Sourced from nixpkgs-master: stable/unstable zulip still build with the
      # EOL-flagged pnpm_10_29_2; master's 5.12.4 moved to pnpm_11, avoiding the
      # insecure-package refusal without an allow-list.
      pkgs-master.zulip
      spotify
      obsidian
      telegram-desktop
      discord
      slack
      google-chrome
      todoist-electron
      libreoffice
      wl-clipboard
      lm_sensors
      smartmontools
      # TODO: Freon Gnome extension is broken when `nvme-cli` is enabled
      # https://github.com/UshakovVasilii/gnome-shell-extension-freon/issues/293
      pkgs-unstable.nvme-cli
      restic
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
      imagemagick
      ghostscript
      inkscape
      # GNOME's image viewer; works fine standalone outside a GNOME session.
      loupe
    ]
    ++ [
      # nvim = the standalone nvf-built editor exposed as packages.nvim
      # at the nixos flake top level. System editor ($EDITOR) stays as
      # plain `vim` for git commit messages.
      inputs.self.packages.${pkgs.system}.nvim

      # Connect to the dev microvm, forwarding its scoped credentials without
      # installing them in the ordinary host-shell environment. Assigning the
      # variables unconditionally prevents ambient host values from crossing
      # the boundary when a VM secret is unavailable.
      (pkgs.writeShellScriptBin "ssh-dev-vm" ''
        export GH_TOKEN="$(cat /run/secrets/gh-token 2>/dev/null)"
        export NIX_CONFIG="$(cat /run/secrets/rendered/nix-access-tokens 2>/dev/null)"
        [ -r /run/secrets/bencher-key ] && export BENCHER_API_KEY="$(cat /run/secrets/bencher-key)"
        # Give the VM the READ-ONLY AWS pair only, never the host's write
        # creds. Set unconditionally with a fallback so a missing RO secret
        # fails closed (empty → no usable creds in the VM) instead of leaking
        # whatever AWS_* the launching host shell holds. The write pair is
        # deliberately absent from the dev-vm SendEnv list (desktop.nix), so a
        # plain `ssh dev-vm` forwards no AWS creds at all; only this wrapper
        # opts in, and only to the RO pair, via the per-invocation SendEnv.
        export AWS_ACCESS_KEY_ID="$(cat /run/secrets/aws-access-key-id-ro 2>/dev/null)"
        export AWS_SECRET_ACCESS_KEY="$(cat /run/secrets/aws-secret-access-key-ro 2>/dev/null)"
        # No explicit command: land in tmux, always — tmux-resume (base.nix)
        # attaches to the running server's most-recent session, or on a fresh
        # boot starts the server (firing continuum's restore) and reattaches
        # the session that was active before the last shutdown, falling back
        # to a fresh ~/repos session only when there's nothing to restore. A
        # Super+T window is therefore never a bare shell, so there's no "am I
        # in tmux?" ambiguity. Detaching falls through to a plain login shell
        # in ~/repos (debugging the tmux/sesh layer itself from inside the
        # window); exiting that shell ends the ssh session and the ghostty
        # window with it.
        if [ "$#" -eq 0 ]; then
          exec ${pkgs.openssh}/bin/ssh \
            -o SendEnv=AWS_ACCESS_KEY_ID -o SendEnv=AWS_SECRET_ACCESS_KEY \
            -t dev-vm 'cd repos 2>/dev/null; "$SHELL" -lc tmux-resume; exec "$SHELL" -l'
        fi
        exec ${pkgs.openssh}/bin/ssh \
          -o SendEnv=AWS_ACCESS_KEY_ID -o SendEnv=AWS_SECRET_ACCESS_KEY \
          dev-vm "$@"
      '')
    ];

  # App-launcher entry: opens host ghostty already ssh'd into the dev
  # microvm, dropping straight into the VM's tmux. Plain ghostty (no
  # args) stays the host-native terminal.
  xdg.desktopEntries.ghostty-dev = {
    name = "Ghostty (dev VM)";
    genericName = "Terminal";
    comment = "Ghostty connected to the dev microvm over VSOCK";
    exec = "ghostty -e ssh-dev-vm";
    icon = "com.mitchellh.ghostty";
    terminal = false;
    categories = [
      "System"
      "TerminalEmulator"
    ];
  };

  # Host kitty — escape hatch for when the dev microvm is unhealthy or
  # when you need a terminal that isn't tied to the VM at all.
  programs.kitty = {
    enable = true;
    font = {
      name = "FiraCode Nerd Font Mono";
      size = 11;
    };
    themeFile = "Catppuccin-Mocha";
    settings = {
      cursor_shape = "beam";
      mouse_hide_wait = "1.0";
      enable_audio_bell = false;
      hide_window_decorations = "yes";
    };
  };

  # Image MIME defaults — Loupe for png/jpg/gif. File-manager defaults
  # (inode/directory) live in the DE-specific overlay since the GNOME
  # session already defaults to Nautilus and Hyprland explicitly sets it.
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "image/png" = [ "org.gnome.Loupe.desktop" ];
      "image/jpeg" = [ "org.gnome.Loupe.desktop" ];
      "image/gif" = [ "org.gnome.Loupe.desktop" ];
    };
  };

  services.podman = {
    enable = true;
  };
}
