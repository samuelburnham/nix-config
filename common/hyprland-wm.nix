# Hyprland desktop — system-level bits for hosts that run Hyprland instead
# of GNOME (currently only the desktop). Sister file to ./gnome-de.nix;
# whichever a host imports decides which graphical environment GDM offers.
# Per the NixOS Hyprland wiki page, `programs.hyprland.enable` already wires
# up polkit, xdg-desktop-portal-hyprland, graphics drivers, fonts, dconf,
# xwayland, and the GDM session entry, so this file stays small.
{
  pkgs,
  ...
}:
{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;

    # Hyprland and its portal come from the module defaults (stable pkgs).
    # The module rewires the portal's `hyprland` dependency to match
    # `package`, but the portal's own IPC protocol version is only
    # guaranteed compatible because nixpkgs pins the two as a tested pair —
    # so if `package` is ever overridden, override `portalPackage` from the
    # same channel. The corresponding home-manager module in
    # home/modules/hyprland.nix sets `package = null; portalPackage = null;`
    # so it picks these up rather than introducing a second version.

    # UWSM runs the compositor as a systemd user unit bound to
    # graphical-session.target, so session services (waybar, swaync, …) are
    # stopped cleanly when the compositor exits instead of crash-looping
    # against a dead Wayland socket until they trip systemd's start limit
    # and stay failed into the next login. Log in via the
    # "Hyprland (uwsm-managed)" GDM entry. GDM also lists a plain "Hyprland"
    # entry — the hyprland package ships both session files and nixpkgs has
    # no option to hide one — but this config only supports the uwsm entry:
    # env lives in ~/.config/uwsm/env*, launch binds go through `uwsm app`,
    # and no session target ever starts in the plain entry, so services
    # like waybar never come up there. The fallback session is GNOME
    # (./gnome-de.nix). Also switches the system D-Bus implementation to
    # dbus-broker (uwsm module default). The home-manager side must keep
    # `systemd.enable = false` — its exec-once env-export/target-start hack
    # would fight uwsm's own session unit management.
    withUWSM = true;
  };

  # Bluetooth — GNOME enabled this transitively; Hyprland does not.
  # Needed for the blueman-applet tray icon and Settings panel.
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # gvfs powers Nautilus' trash, recent files, network mounts, and MTP
  # support. GNOME enables it implicitly; under Hyprland we set it directly.
  services.gvfs.enable = true;

  # gnome-keyring stores secrets for Bitwarden/browsers etc. GDM unlocks the
  # default keyring at login via PAM when this is enabled.
  services.gnome.gnome-keyring.enable = true;

  # The GNOME fallback session (./gnome-de.nix) defaults i18n input to ibus.
  # Nothing integrates ibus under Hyprland — it just XDG-autostarts a pile of
  # daemons and, since ibus 1.5.33, pops a "should be called from the desktop
  # session in Wayland" notification at every login. No complex input methods
  # are used here, so disable it host-wide; a plain keyboard layout needs no
  # IM daemon in the GNOME session either.
  i18n.inputMethod.enable = false;

  # Hint Electron/Chromium apps (Slack, Discord, VS Code, Chrome) to use
  # Wayland natively — without this they capture via XWayland and screen
  # sharing breaks. Documented at:
  # https://nixos.wiki/wiki/Hyprland and
  # https://wiki.hypr.land/Useful-Utilities/Screen-Sharing/
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # XDG portal — `programs.hyprland.enable` already registers
  # xdg-desktop-portal-hyprland. The Hyprland portal handles ScreenCast and
  # Screenshot; the gtk portal handles FileChooser and AppChooser. Listing
  # the order silences the "no default portal" warning that nixpkgs prints
  # on activation. The gtk portal comes from `pkgs` (stable) — it has no
  # version coupling with Hyprland.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [
      "hyprland"
      "gtk"
    ];
  };
}
