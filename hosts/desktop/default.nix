# Desktop-specific NixOS system configuration
# Gigabyte B650I AMD desktop
{
  config,
  pkgs,
  inputs,
  username,
  ...
}:
{
  imports = [
    ../../common/host.nix
    # Desktop primarily runs Hyprland; the matching home-manager overlay
    # (home/modules/hyprland.nix) is wired via home/profiles/desktop.nix in
    # flake.nix. GNOME stays installed alongside as a fallback —
    # both desktop entries appear in GDM, pick whichever at login.
    ../../common/hyprland-wm.nix
    ../../common/gnome-de.nix
    # Root-owned /etc/claude-code/managed-settings.json — the enforced deny
    # policy for the host-side Claude (home/profiles/desktop.nix), which it
    # can't edit as an unprivileged user.
    ../../common/claude-managed-settings.nix
    ./hardware-configuration.nix
    ./microvm.nix
    ./restic.nix
  ];

  # Renaming this breaks `rebuild` until bootstrapped: `nixos-rebuild
  # switch` resolves `nixosConfigurations.<hostname>` by default, so a
  # new name here must be mirrored in the flake's `nixosConfigurations`
  # key (flake.nix) in the same commit. After the rename, run
  # the first switch with the new key explicit, e.g.
  #   nixos-rebuild switch --flake /home/sam/repos/nix-config#newname --sudo
  # (or run `sudo hostname newname` first so the default lookup hits
  # the new key). Subsequent `rebuild` invocations work normally.
  networking.hostName = "nixos"; # Define your hostname.
  #networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Fixes suspend issue on Gigabyte B650I motherboard
  # Note: If DDR5 RAM XMP profile is enabled, resuming from suspend may fail
  # I noticed this once in the NixOS boot log: `bug: bad page state in process swapper`
  # If so, lower the RAM speed in BIOS incrementally and test. E.g. 6400Mhz might fail, but 6000Mhz usually works
  boot.kernelParams = [ "acpi_osi=\"!Windows 2015\"" ];
  systemd.services.disable-xh00-wakeup = {
    description = "Disable XH00 device wakeup";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "disable-xh00-wakeup" ''
        if grep -q "XH00.*enabled" /proc/acpi/wakeup; then
          echo "XH00" > /proc/acpi/wakeup
        fi
      '';
    };
    wantedBy = [ "multi-user.target" ];
  };
  # Enable wakeup for Kinesis keyboard
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="29ea", ATTRS{idProduct}=="0362", ATTR{power/wakeup}="enabled"
  '';

  # Logitech Bolt receiver (046d:c548). Without hid-logitech-hidpp the HID
  # nodes fall back to hid-generic, which speaks no HID++, so the kernel
  # cannot tell when a paired wireless device drops off the receiver: a
  # sleeping or out-of-range mouse is indistinguishable from a live one.
  # There is no disconnect event, the input node persists, and the pointer
  # silently stops until the mouse is power-cycled. The driver also exposes
  # charge level under /sys/class/power_supply, which is otherwise empty.
  boot.kernelModules = [ "hid_logitech_hidpp" ];
  hardware.logitech.wireless = {
    enable = true;
    enableGraphical = true;
  };

  # DDC/CI brightness control for the DisplayPort monitors. A desktop panel
  # has no backlight sysfs, so brightness is driven over the monitor's I2C
  # channel with ddcutil (VCP feature 0x10). hardware.i2c.enable loads
  # i2c-dev, creates /dev/i2c-*, and defines the i2c group; the user must be
  # in that group for non-root access. DDC/CI must also be enabled in the
  # monitor's own OSD menu for any of this to take effect.
  hardware.i2c.enable = true;
  users.users.${username}.extraGroups = [ "i2c" ];
  environment.systemPackages = [ pkgs.ddcutil ];

  # WiFi workarounds — neither solved poor connection after resuming from suspend
  # Solution: use Ethernet
  # networking.networkmanager.wifi = {
  #   scanRandMacAddress = false;
  #   powersave = false;
  # };

  # 16 GB swapfile as overflow under memory pressure.
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024;
    }
  ];

  # Prefer reclaiming file-backed cache over anonymous memory.
  boot.kernel.sysctl."vm.swappiness" = 10;

  # ~1 GiB free-page reserve (default caps at 66 MiB regardless of RAM).
  # Keeps kswapd reclaiming in the background ahead of allocation bursts —
  # e.g. the dev VM's guest dirtying memory at GiB/s — so host threads
  # don't fall into synchronous direct reclaim, which stalls whichever
  # thread is allocating (compositor frames, input handling).
  boot.kernel.sysctl."vm.min_free_kbytes" = 1048576;

  # The graphical session's last 1 GiB is never reclaimed, so the
  # compositor/input core stays resident no matter what eats the rest of
  # the host's RAM. Without a floor, reclaim can evict Hyprland's input
  # thread until it falls behind draining the mouse's evdev ring buffer;
  # the overflow (SYN_DROPPED) wedges the pointer until the device is
  # re-opened. Kept small on purpose: memory.min is honored even at the
  # cost of an OOM kill, so a large floor could turn pressure into kills.
  systemd.slices.user.sliceConfig.MemoryMin = "1G";

  # TODO: Fix printing once new CUPS version is release
  # Had to remove and re-add printer in Gnome settings after adding the driver
  services.printing.drivers = [ pkgs.brlaser ];

}
