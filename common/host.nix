# Host-machine system configuration — the full workstation layer for the
# physical hosts (desktop + laptop) on top of common/base.nix: bootloader,
# sops, GUI/desktop, networking, printing, audio. The dev microvm does NOT
# import this; it shares only common/base.nix.
{
  config,
  pkgs,
  inputs,
  username,
  ...
}:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    ./base.nix
  ];
  # Use the Grub2 boot loader with EFI.
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    useOSProber = true;
    devices = [ "nodev" ];
    # Boot-menu entry into the BIOS, instead of remembering which key to
    # spam at POST. `systemctl reboot --firmware-setup` does the same
    # from a running session.
    extraEntries = ''
      menuentry "UEFI Firmware Settings" {
        fwsetup
      }
    '';
  };
  boot.loader.efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/boot";
  };

  # Reboot/shutdown otherwise stalls ~90s on "A stop job is running for User
  # Manager for UID 1000": xdg-document-portal's FUSE mount (/run/user/1000/doc)
  # ignores SIGTERM, so the user manager waits out the full stop timeout before
  # SIGKILLing it. Cap the user manager's default stop timeout so stragglers are
  # killed promptly. Scoped to user services only — system services (e.g. the
  # dev microvm) keep their full graceful-shutdown window.
  systemd.user.extraConfig = "DefaultTimeoutStopSec=10s";

  boot.enableContainers = true;
  virtualisation.containers.enable = true;

  # Enable networking
  networking.networkmanager.enable = true;

  # time.timeZone, i18n.defaultLocale, the nix experimental-features, the
  # editor, and allowUnfree are shared with the guest via ./base.nix.

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  # Not set explicitly but Wayland is enabled and the default
  services.xserver.enable = true;

  # GDM works as the display manager for both GNOME and Hyprland sessions;
  # which desktop is offered is decided by which of ./gnome-de.nix or
  # ./hyprland-wm.nix the host imports.
  services.displayManager.gdm.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Pressure-based OOM killing for the user session: when a user slice spends
  # >80% of its time stalled on memory (sustained), systemd-oomd SIGKILLs the
  # worst-offending descendant cgroup — with apps launched as uwsm scopes
  # (home/modules/hyprland.nix), that's one app, not the whole session. Kills
  # during the swap-thrash phase instead of after minutes of frozen desktop
  # waiting for the kernel OOM killer. User slices only, deliberately: the
  # dev microvm lives in system.slice, so under combined pressure (VM holding
  # RAM + a heavy host app) oomd kills the host app's scope and can never
  # pick the VM. The oomd daemon itself is on by default; this option is
  # what marks the slices for it.
  systemd.oomd.enableUserSlices = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.${username} = {
    isNormalUser = true;
    description = "Sam Burnham";
    extraGroups = [
      "networkmanager"
      "wheel"
      # microvm host runs cloud-hypervisor as microvm:kvm; this lets the
      # user reach /var/lib/microvms/*/notify.vsock for ssh-over-VSOCK.
      "kvm"
    ];
  };

  # Secrets management with sops-nix
  # Note: When setting up a new NixOS device, get the Age private key from password manager.
  # Then run:
  # ```
  # mkdir -p ~/.config/sops/age
  # vim ~/.config/sops/age/keys.txt
  # ```
  # Then paste the contents, save, and rebuild NixOS
  # Check encrypted file by opening `~/repos/nix-config/secrets/secrets.yaml`
  # Open decrypted file by running `sops ~/repos/nix-config/secrets/secrets.yaml`
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.keyFile = "/home/${username}/.config/sops/age/keys.txt";

    secrets = {
      # Read-only GitHub PAT for the dev microvm. The host keeps the decrypted
      # file solely so ssh-dev-vm can forward it; host shells and the host Nix
      # daemon authenticate independently.
      gh-token = {
        mode = "0400";
        owner = username;
      };

      # AWS + GCP credentials for Terraform and the cloud CLIs, read by the
      # user's shell rc and exported (see base.nix). aws-* are the access-key
      # pair; gcp-credentials is a service-account JSON that
      # GOOGLE_APPLICATION_CREDENTIALS points at.
      aws-access-key-id = {
        mode = "0400";
        owner = username;
      };
      aws-secret-access-key = {
        mode = "0400";
        owner = username;
      };
      # Read-only AWS key pair — an IAM identity scoped to Get/List/Describe
      # plus read on the Terraform state bucket, with no write/create/delete.
      # The ssh-dev-vm wrapper (home/modules/gui.nix) forwards THIS pair into
      # the dev microvm instead of the write pair above, so Claude in the VM
      # can run `terraform plan` but cannot mutate infrastructure even if it
      # evades the Bash deny rules — AWS IAM refuses the write at the API. The
      # write pair never leaves the host. Both values come from secrets.yaml;
      # create the scoped IAM user in AWS first (see change notes).
      aws-access-key-id-ro = {
        mode = "0400";
        owner = username;
      };
      aws-secret-access-key-ro = {
        mode = "0400";
        owner = username;
      };
      # Bencher API key (`bencher_user_*`), read by the user's shell rc and
      # exported as BENCHER_API_KEY. API keys replace the deprecated JWT
      # API tokens (`--token`/BENCHER_API_TOKEN).
      bencher-key = {
        mode = "0400";
        owner = username;
      };
      # Cachix write token for samuelburnham.cachix.org, the cache this flake
      # publishes to. Named per cache because cachix keys its auth token
      # globally, not per cache, so each one needs its own secret and its own
      # scope. Held on the host only: the dev microvm is deliberately given no
      # credential that can write to a shared artifact store.
      cachix-token-samuelburnham = {
        mode = "0400";
        owner = username;
      };
      # RunsOn license for the self-hosted CI runners in terraform-server.
      # Deliberately not exported by the shell rc and not forwarded into the
      # dev microvm: terraform-server's own dev shell reads this file and
      # exports TF_VAR_runs_on_license_key while inside that repo, so the key
      # is in the environment there and nowhere else.
      runs-on-license-key = {
        mode = "0400";
        owner = username;
      };
      # GCP disabled for now — no service-account key yet. Re-enable once
      # `gcp-credentials` is added to secrets.yaml (and the export in base.nix).
      # gcp-credentials = {
      #   mode = "0400";
      #   owner = username;
      # };
    };

    # Render the VM's Nix access-token setting without duplicating the PAT in
    # secrets.yaml. Only ssh-dev-vm reads this file for forwarding.
    templates.nix-access-tokens = {
      content = "access-tokens = github.com=${config.sops.placeholder.gh-token}";
      owner = username;
    };
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
    git
    sops
    usbutils
  ];

  # Increase `sudo` timeout to 30 minutes
  security.sudo.extraConfig = "Defaults timestamp_timeout=30";

  programs.steam.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  networking.firewall.enable = true;
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
