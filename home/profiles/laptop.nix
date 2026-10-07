# sam@laptop — Intel, MSI
{
  lib,
  pkgs,
  gnomeBaseExtensions,
  ...
}:
{
  imports = [
    ../modules/base.nix
    ../modules/alias.nix
    ../modules/gnome.nix
    # The laptop is a daily driver where claude runs directly against real
    # repos, so it carries claude.nix (prompting default + bubblewrap sandbox
    # kept, same as the desktop host) and worktrunk, which shells out to claude
    # for commit messages.
    ../modules/claude.nix
    ../modules/worktrunk.nix
  ];

  home.packages = with pkgs; [
    thunderbird
    # Gaming overlay for FPS, temps, CPU/GPU load
    mangohud
    # Use Gnome/`powerprofilesctl` Performance mode on AC charging, Balanced mode on battery
    gnomeExtensions.auto-power-profile
    # Enable hibernate, suspend-to-hibernate, and reboot to BIOS in Gnome power menu. When finished with the laptop for the day/overnight, hibernate or suspend-to-hibernate will allow resuming progress later. Simply closing the lid and unplugging any USB peripherals will also suspend-to-hibernate per systemd settings in configuration.nix
    gnomeExtensions.power-off-options
  ];

  # GNOME: Set enabled-extensions for laptop (shared + laptop-specific).
  # pop-shell is dropped from the shared base here: its auto-tiler reflows any
  # window mutter resizes, which cancels the <Super>a/d half-screen snap. The
  # desktop's GNOME fallback still enables it, so the filter is host-local.
  dconf.settings = {
    "org/gnome/shell".enabled-extensions = map (e: e.extensionUuid) (
      (lib.filter (
        e: e.extensionUuid != pkgs.gnomeExtensions.pop-shell.extensionUuid
      ) gnomeBaseExtensions)
      ++ (with pkgs.gnomeExtensions; [
        auto-power-profile
        power-off-options
      ])
    );
    # Laptop-specific keybind, plus the four binds gnome.nix blanks to make
    # room for pop-shell's focus/monitor keys — restored to GNOME's own
    # defaults now that nothing consumes them here.
    "org/gnome/desktop/wm/keybindings" = {
      close = [ "<Shift><Control>w" ];
      minimize = lib.mkForce [ "<Super>h" ];
      move-to-monitor-up = lib.mkForce [ "<Super><Shift>Up" ];
      move-to-monitor-down = lib.mkForce [ "<Super><Shift>Down" ];
    };
    "org/gnome/settings-daemon/plugins/media-keys" = {
      screensaver = lib.mkForce [ "<Super>l" ];
    };
    "org/gnome/desktop/notifications/application/spotify" = {
      enable = false;
    };
  };
}
