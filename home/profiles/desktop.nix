# sam@desktop — AMD, Gigabyte B650I
{
  pkgs,
  gnomeBaseExtensions,
  ...
}:
{
  imports = [
    ../modules/base.nix
    ../modules/alias.nix
    # Hyprland is the primary session; GNOME is imported alongside as a
    # fallback so logging into the GNOME entry in GDM gives the full
    # pop-shell setup (keybinds, favourites, dconf) rather than a stripped
    # session. The two overlays set several of the same options
    # (programs.ghostty, services.podman, xdg.mimeApps) to identical
    # values, which Nix merges cleanly; home.packages overlaps duplicate
    # harmlessly in the list. Drop ../modules/gnome.nix once Hyprland is
    # settled to halve the build closure.
    ../modules/hyprland.nix
    ../modules/gnome.nix
    # Host-side Claude for debugging the Hyprland/waybar setup the dev VM
    # can't see (the compositor runs here, not in the guest). The host keeps
    # claude.nix's prompting defaultMode; only the disposable VM / cloud box
    # default to "auto".
    ../modules/claude.nix
    # worktrunk drives worktree-based dev on the workstation too; it shells
    # out to the claude above for commit messages.
    ../modules/worktrunk.nix
    ../modules/codex.nix
  ];

  # direnv and git hooks auto-run repo-local files (.envrc and its devshell;
  # .git/hooks) from whatever working tree you're in. ~/repos is the same
  # tree the dev microvm builds in, so keep that auto-execution confined to
  # the VM: disable both on the host (base.nix leaves them on, which the VM
  # keeps), leaving the host for git push + backup. hooksPath points at a
  # read-only empty store dir.
  programs.direnv.enable = false;
  programs.git.settings.core.hooksPath = "${pkgs.emptyDirectory}";

  # ssh dev-vm → ssh-over-VSOCK into the dev microvm as sam. systemd ships
  # an ssh_config snippet that ProxyCommands `vsock-mux/*` hosts through
  # systemd-ssh-proxy, but it only matches when that literal pattern is the
  # host argument — an alias with HostName set doesn't trigger it, so the
  # ProxyCommand is replicated here against the same helper.
  programs.ssh = {
    enable = true;
    # HM's implicit `Host *` defaults are deprecated. They only restated
    # ssh's own built-in defaults, so opt out and keep ssh's defaults
    # rather than re-declaring an empty block.
    enableDefaultConfig = false;
    settings.dev-vm = {
      HostName = "vsock-mux/var/lib/microvms/dev/notify.vsock";
      User = "sam";
      ProxyCommand = "${pkgs.systemd}/lib/systemd/systemd-ssh-proxy %h %p";
      # Forward credentials that ssh-dev-vm defines for its child ssh process;
      # ordinary host shells do not contain the VM's GitHub credentials.
      # sshd in the VM accepts the same names via AcceptEnv.
      #
      # AWS_* is deliberately NOT here: the host's write creds live under
      # those names, and a plain `ssh dev-vm` must never forward them into the
      # VM. The ssh-dev-vm wrapper (home/modules/gui.nix) opts its own session
      # in with a per-invocation `-o SendEnv` carrying only the read-only pair.
      SendEnv = [
        "GH_TOKEN"
        "NIX_CONFIG"
        "BENCHER_API_KEY"
      ];
      ProxyUseFdpass = "yes";
      CheckHostIP = "no";
      StrictHostKeyChecking = "no";
      UserKnownHostsFile = "/dev/null";
      # /dev/null known-hosts means ssh re-"adds" the key every connect
      # and prints a warning each time; ERROR drops that notice while
      # still surfacing real failures.
      LogLevel = "ERROR";
    };
  };

  # GNOME: Set enabled-extensions for desktop (shared extensions only).
  # Inert under Hyprland — dconf state without gnome-shell to consume it.
  dconf.settings."org/gnome/shell".enabled-extensions = map (e: e.extensionUuid) gnomeBaseExtensions;
}
