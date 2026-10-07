# GNOME desktop-manager — system-level bits for hosts that offer a GNOME
# session: the laptop's primary desktop, and the desktop's GDM fallback
# alongside Hyprland (imported next to ./hyprland-wm.nix there). host.nix
# keeps GDM, X server, fonts, audio, etc. shared.
{
  pkgs,
  ...
}:
{
  services.desktopManager.gnome.enable = true;
  services.gnome.games.enable = false;

  environment.gnome.excludePackages = with pkgs; [
    gnome-calendar
    epiphany
    geary
    gnome-music
  ];
}
