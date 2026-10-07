# GNOME workstation overlay — imported by NixOS hosts that run a full
# GNOME desktop (see hosts/laptop and hosts/desktop's GNOME fallback).
# Holds only GNOME-specific bits (extensions, dconf, pop-launcher); the
# shared GUI applications, Ghostty, MIME defaults, and Podman live in
# ./gui.nix.
{
  pkgs,
  ...
}:
let
  # Base GNOME shell extensions shared by every GNOME host. Used as packages
  # below and, via _module.args, as dconf enabled-extensions UUIDs in each
  # host (which append their own extras) — defined once so the package list
  # and the enabled-extensions list can't drift.
  baseExtensions = with pkgs.gnomeExtensions; [
    pop-shell
    caffeine
    # Official Gnome top bar display for CPU, RAM, swap, and network usage
    system-monitor
    # Comprehensive top bar display for system info, I just use it for temps and fan speed
    vitals
    # Start apps in a specific workspace
    auto-move-windows
  ];
in
{
  imports = [
    ./gui.nix
  ];

  _module.args.gnomeBaseExtensions = baseExtensions;

  home.packages = [
    # Search backend for the pop-shell launcher (Super+/); the extension
    # alone is just the UI and returns nothing without this daemon.
    pkgs.pop-launcher
  ]
  ++ baseExtensions;

  # These settings can be found in `dconf-editor` or by running `dconf watch /` and then
  # editing GUI settings, which will print values in the terminal.
  # Each host must set dconf "org/gnome/shell".enabled-extensions separately.
  dconf = {
    enable = true;
    settings = {
      "org/gnome/shell/extensions/pop-shell" = {
        tile-by-default = true;
        active-hint = true;
        # Translucent blue accent — subtle in both light and dark mode.
        hint-color-rgba = "rgba(53, 132, 228, 0.4)";
        focus-down = [ "<Super>j" ];
        focus-left = [ "<Super>h" ];
        focus-right = [ "<Super>l" ];
        focus-up = [ "<Super>k" ];
        tile-enter = [ "<Super>BackSpace" ];
        tile-move-down = [ "<Shift>j" ];
        tile-move-left = [ "<Shift>h" ];
        tile-move-right = [ "<Shift>l" ];
        tile-move-up = [ "<Shift>k" ];
        tile-resize-down = [ "j" ];
        tile-resize-left = [ "h" ];
        tile-resize-right = [ "l" ];
        tile-resize-up = [ "k" ];
        tile-swap-down = [ "<Primary>j" ];
        tile-swap-left = [ "<Primary>h" ];
        tile-swap-right = [ "<Primary>l" ];
        tile-swap-up = [ "<Primary>k" ];
        # Pop-shell's tree-aware cross-monitor move; the GNOME-native
        # move-to-monitor-* equivalents fight the auto-tiler (window
        # snaps back to its old monitor) so they're cleared below.
        pop-monitor-up = [ "<Shift><Super>Up" ];
        pop-monitor-down = [ "<Shift><Super>Down" ];
        pop-monitor-left = [ ];
        pop-monitor-right = [ ];
        pop-workspace-down = [ ];
        pop-workspace-up = [ ];
      };
      "org/gnome/desktop/wm/keybindings" = {
        # Cleared in favor of pop-monitor-up/down above (pop-shell tree-aware).
        move-to-monitor-down = [ ];
        move-to-monitor-up = [ ];
        # TODO: This is set but not working on laptop
        move-to-workspace-left = [ "<Shift><Super>Left" ];
        move-to-workspace-right = [ "<Shift><Super>Right" ];
        switch-to-workspace-left = [ "<Super>Left" ];
        switch-to-workspace-right = [ "<Super>Right" ];
        switch-to-workspace-1 = [ "<Super>Home" ];
        switch-to-workspace-last = [ "<Super>End" ];
        # TODO: Make this Alt-Tab on laptop
        switch-windows = [ "<Alt>f" ];
        switch-windows-backward = [ "<Shift><Alt>f" ];
        maximize = [ "<Super>Up" ];
        unmaximize = [ "<Super>Down" ];
        #close = ["<Shift><Control>w"];
        toggle-fullscreen = [ "<Alt><Super>f" ];
        activate-window-menu = [ "<Super>equal" ];
        # Freed for pop-shell focus-left (<Super>h).
        minimize = [ ];
      };
      "org/gnome/shell/keybindings" = {
        toggle-application-view = [ "<Super>Tab" ];
      };
      # Mutter's half-screen snap, moved off its <Super>Left/Right default so
      # those reach switch-to-workspace-left/right above.
      "org/gnome/mutter/keybindings" = {
        toggle-tiled-left = [ "<Super>a" ];
        toggle-tiled-right = [ "<Super>d" ];
      };
      "org/gnome/mutter" = {
        dynamic-workspaces = false;
        workspaces-only-on-primary = false;
      };
      "org/gnome/desktop/wm/preferences" = {
        num-workspaces = 4;
      };
      # TODO: org.gnome.settings-daemon.plugins.media-keys for play/pause & volume control
      "org/gnome/settings-daemon/plugins/media-keys" = {
        custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
        ];
        # Freed for pop-shell focus-right (<Super>l).
        screensaver = [ ];
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
        binding = "<Control><Alt>t";
        command = "ghostty";
        name = "Launch Terminal";
      };
      "org/gnome/shell" = {
        favorite-apps = [
          "com.mitchellh.ghostty.desktop"
          "firefox.desktop"
          "org.gnome.Nautilus.desktop"
          "zulip.desktop"
          "spotify.desktop"
        ];
      };
      "org/gnome/desktop/interface" = {
        clock-format = "12h";
        color-scheme = "prefer-dark";
      };
      "org/gtk/settings/file-chooser" = {
        clock-format = "12h";
      };
      "org/gnome/desktop/sound" = {
        event-sounds = false;
      };
      "org/gnome/settings-daemon/plugins/color" = {
        night-light-enabled = true;
      };
      # "org/gnome/desktop/notifications/application/spotify" = {
      #   enable = false;
      # };
      # TODO: Add weather in "org/gnome/Weather/locations" and/or "org/gnome/shell/weather/locations"
    };
  };
}
