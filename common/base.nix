# Shared NixOS base for both the host and the dev microvm guest — the
# system-level counterpart to home/modules/base.nix. Holds the config both
# systems need; host-only concerns (bootloader, sops, desktop, …) stay in
# common/host.nix, and guest-only concerns (microvm.*, gc, …) in
# hosts/desktop/microvm.nix.
{ ... }:
{
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # @wheel rather than a single named user, so it covers the host and
    # guest accounts uniformly.
    trusted-users = [ "@wheel" ];
  };

  # System editor for root and pre-login contexts: neovim with vi/vim
  # aliases (so vi, vim, and nvim all launch it) and EDITOR=nvim, plus nano
  # removed so nothing falls back to it. The user's own configured nvim
  # comes from home-manager (home/modules/base.nix).
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = true;
  };
  programs.nano.enable = false;
}
