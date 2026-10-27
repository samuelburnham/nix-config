# Hosts the `dev` microvm where ghostty + tmux + claude + builds run.
# Host keeps Hyprland + a kitty escape-hatch; everything inside ghostty
# crosses the cloud-hypervisor boundary.
{
  inputs,
  pkgs,
  config,
  lib,
  username,
  ...
}:
let
  vmName = "dev";
  guestUid = 1000;
  bridgeIface = "br-microvm";
  bridgeAddr = "10.0.0.1";
  bridgePrefix = 24;
  vmAddr = "10.0.0.2";
  vmMac = "02:00:00:00:00:02";
  # Host's primary NIC — receives MASQUERADE'd outbound traffic from the VM.
  externalIface = "enp13s0";
in
{
  imports = [ inputs.microvm.nixosModules.host ];

  # Bridge with no slave interfaces; VM TAPs attach via microvm.interfaces.
  networking.bridges.${bridgeIface}.interfaces = [ ];
  networking.interfaces.${bridgeIface}.ipv4.addresses = [
    {
      address = bridgeAddr;
      prefixLength = bridgePrefix;
    }
  ];

  # NAT outbound for the VM subnet.
  networking.nat = {
    enable = true;
    enableIPv6 = false;
    internalInterfaces = [ bridgeIface ];
    externalInterface = externalIface;
  };

  # Allow DHCP + DNS replies from dnsmasq on the bridge.
  networking.firewall.interfaces.${bridgeIface} = {
    allowedUDPPorts = [
      53
      67
    ];
    allowedTCPPorts = [ 53 ];
  };

  # DHCP + DNS for the VM behind the bridge.
  services.dnsmasq = {
    enable = true;
    settings = {
      interface = bridgeIface;
      bind-interfaces = true;
      dhcp-range = [ "10.0.0.10,10.0.0.100,12h" ];
      dhcp-host = [ "${vmMac},${vmAddr}" ];
      # Forward upstream queries via the host's resolver
      server = [
        "1.1.1.1"
        "8.8.8.8"
      ];
    };
  };

  microvm.autostart = [ vmName ];

  # Make microvm@ services Type=notify: cloud-hypervisor forwards the
  # guest's sd_notify(READY) over the vsock, so the unit only reaches
  # "started" once the VM has actually booted. This lets the vsock-perms
  # ExecStartPost below run a single chmod (the socket provably exists by
  # then) instead of polling. Requires every microvm on this host to send
  # readiness — our NixOS guest's systemd does.
  microvm.host.useNotifySockets = true;

  # Slight CPU priority drop for the VM so host UI processes win when both
  # compete. Default weight is 100; 80 yields ~20% more host cycles under
  # contention. VM perf at idle host is unaffected.
  #
  # cloud-hypervisor creates notify.vsock owner-only (0700); group-rw lets
  # the kvm group ssh-over-VSOCK without sudo. With Type=notify (above) the
  # socket exists by the time ExecStartPost runs, so a single chmod does
  # it. Runs as the microvm service user, which owns the socket.
  systemd.services."microvm@${vmName}".serviceConfig = {
    CPUWeight = 80;
    ExecStartPost = [
      "${pkgs.coreutils}/bin/chmod g+rw /var/lib/microvms/${vmName}/notify.vsock"
    ];
  };

  # The guest can consume 48 GiB of host RAM. Suspend needs additional host
  # memory for amdgpu VRAM eviction; under memory pressure this can fail after
  # the display is already off. Stop the guest before every suspend entry
  # point to release that memory.
  #
  # sleep-actions.service is ordered Before=sleep.target, so the stop below
  # completes — memory genuinely returned — before the kernel suspends. The
  # `is-active` probe and the stop have to sit in one sequential script: a
  # declarative Conflicts=sleep.target on the unit would stop the VM
  # concurrently with this script, and the probe would then race a unit already
  # reading as "deactivating" and lose the state needed to restore it.
  powerManagement.powerDownCommands = ''
    if ${pkgs.systemd}/bin/systemctl is-active --quiet microvm@${vmName}.service; then
      ${pkgs.coreutils}/bin/touch /run/microvm-${vmName}-restore
      ${pkgs.systemd}/bin/systemctl stop microvm@${vmName}.service
    fi
  '';

  # Bring it back on resume, but only when the suspend is what took it down —
  # a VM stopped by hand to free RAM stays stopped. The flag lives on /run, so
  # a crash between the two hooks resolves itself at the next boot.
  #
  # --no-block because microvm@ is Type=notify: a blocking start would hold the
  # resume path until the guest finished booting and sent READY.
  powerManagement.resumeCommands = ''
    if [ -e /run/microvm-${vmName}-restore ]; then
      ${pkgs.coreutils}/bin/rm -f /run/microvm-${vmName}-restore
      ${pkgs.systemd}/bin/systemctl --no-block start microvm@${vmName}.service
    fi
  '';

  microvm.vms.${vmName} =
    let
      system = "x86_64-linux";
      vmPkgs-unstable = import inputs.nixpkgs-unstable {
        inherit system;
        config.allowUnfreePredicate = pkg: lib.getName pkg == "obsidian-headless";
      };
      vmPkgs-master = import inputs.nixpkgs-master {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # Host rebuilds install the new guest generation without interrupting
      # active sessions. Apply it with `sudo systemctl restart microvm@dev`.
      # home.img, the writable store overlay and nix-var.img survive the
      # restart; regInfo registers the new system closure in the guest Nix DB.
      restartIfChanged = false;

      # null → microvm instantiates the guest's package set from its own
      # nixpkgs.config (allowUnfree lives in common/base.nix) using the
      # host's nixpkgs path, and applies the microvm guest overlay. An
      # externally-built pkgs would instead make nixpkgs.config an error.
      pkgs = null;
      specialArgs = {
        inherit
          inputs
          username
          ;
        pkgs-unstable = vmPkgs-unstable;
        pkgs-master = vmPkgs-master;
      };

      config =
        {
          config,
          pkgs,
          lib,
          username,
          ...
        }:
        {
          imports = [
            inputs.home-manager.nixosModules.home-manager
            ../../common/base.nix
            # Root-owned /etc/claude-code/managed-settings.json — the deny
            # policy Claude runs under in the VM but can't edit from inside it.
            ../../common/claude-managed-settings.nix
          ];

          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";
          home-manager.extraSpecialArgs = {
            inherit inputs username;
            pkgs-unstable = vmPkgs-unstable;
            pkgs-master = vmPkgs-master;
          };
          home-manager.users.${username} = import ../../home/profiles/dev-vm.nix;

          networking.hostName = "dev-vm";
          system.stateVersion = "25.11";

          microvm = {
            hypervisor = "cloud-hypervisor";
            # All 24 host logical CPUs visible to the guest. CPUWeight on the
            # microvm@dev unit lets host UI processes outbid VM threads when
            # both compete.
            vcpu = 24;
            # Flat allocation, no balloon: 48 GiB of the 64 GiB installed.
            # KVM backs pages lazily, but guest page cache pins host memory
            # once dirtied, so treat the ceiling as eventually-resident. The
            # guest must never be swapped by the host — that invalidates
            # benchmark numbers, and the reclaim thrash can starve the
            # compositor's input thread until the pointer wedges. What
            # remains (~14 GiB usable) keeps Hyprland, cloud-hypervisor
            # itself, and a heavy browser resident without touching the
            # 16 GiB swapfile, which is an emergency lane only.
            mem = 49152;

            # CID 2 is the host; 3 is the first guest.
            vsock.cid = 3;
            vsock.ssh.enable = true;

            # An immutable image exposes only the guest system closure and
            # avoids a host virtiofsd process. Repositories live in home.img;
            # the guest has no shared host directories.
            shares = [ ];
            storeOnDisk = true;
            storeDiskType = "erofs";

            # Guest builds write to a persistent upper layer over the image.
            writableStoreOverlay = "/nix/.rw-store";
            volumes = [
              {
                # Writable upper layer over the read-only guest store image —
                # holds paths built or fetched inside the VM that aren't in
                # the image (nix builds, devshell closures, flake fetches).
                # Big ceiling for heavy ZK/Rust/Lean toolchains;
                # sparse, so it only consumes what's actually written.
                #
                # This upper layer persists across reboots, so in-VM `nix` GC
                # leaves overlayfs whiteouts here that mask paths in the
                # read-only lower store, and an unclean host shutdown can
                # corrupt its ext4. After a host NixOS upgrade the guest's new
                # closure may need a path a stale whiteout hides — activation
                # then fails in stage 1 (binaries can't load their libs) and
                # the VM drops to an emergency/freeze instead of booting. The
                # tell is the overlay /nix/store listing fewer entries than
                # /nix/.ro-store. If a fresh boot breaks after an upgrade,
                # delete this image — it only caches rebuildable VM-built
                # paths, and home.img is separate. Stop the VM before removing
                # its disk; microvm recreates it empty on the next start:
                #   systemctl stop microvm@dev
                #   rm /var/lib/microvms/dev/nix-store-overlay.img
                #   systemctl start microvm@dev
                # After this the persistent Nix DB (nix-var.img) still references
                # the deleted upper-layer paths; the nix-db-selfheal service
                # prunes them on the next boot (or `rm nix-var.img` too for a
                # clean slate).
                image = "nix-store-overlay.img";
                mountPoint = "/nix/.rw-store";
                size = 512 * 1024;
              }
              {
                # Persistent VM home — all home state (cargo, claude, tmux,
                # direnv, history, caches) and ~/repos survive reboots here. It
                # is not in the host's restic backup, so work is safe only
                # once pushed. Sparse image (truncate), so the size is a
                # ceiling, not upfront usage.
                image = "home.img";
                mountPoint = "/home";
                size = 128 * 1024;
              }
              {
                # Persistent Nix DB. Off the tmpfs root so the SQLite validity
                # DB survives restarts — otherwise each restart wipes it and the
                # first `nix develop` re-registers the whole devshell closure (a
                # ~1-min stall), because the boot-time regInfo covers only the
                # system closure while the overlay upper layer holds tens of
                # thousands of built paths. Persisting the DB keeps it consistent
                # with the already-persistent overlay it describes. The neededForBoot
                # promotion below makes this a stage-1 mount, present before
                # postBootCommands' `nix-store --load-db`, which creates the
                # /nix/var/nix skeleton itself (LocalStore init) — so a fresh
                # image needs no seeding. Sparse; the DB is tens of MB. This is
                # NOT an upstream-supported pattern: microvm's docs treat the
                # DB-forgets-on-reboot behaviour as unsolved and suggest wiping
                # the overlay each boot instead, which would defeat the build
                # cache — hence the self-heal service below covers the edge cases.
                image = "nix-var.img";
                mountPoint = "/nix/var";
                size = 2 * 1024;
              }
            ];

            interfaces = [
              {
                type = "tap";
                id = "vm-${vmName}";
                mac = vmMac;
              }
            ];

            # microvm creates the host-side TAP but doesn't bridge it. Enslave
            # it to br-microvm (created on the host) so the guest's NIC has an
            # L2 path to the bridge IP (10.0.0.1) — and thus to dnsmasq (DNS)
            # and NAT (outbound internet). Without this the TAP is dangling:
            # ssh still works (VSOCK, not IP), but DNS and `nix build` fail.
            binScripts.tap-up = lib.mkAfter ''
              ${pkgs.iproute2}/bin/ip link set dev 'vm-${vmName}' master '${bridgeIface}'
            '';
          };

          # microvm only marks the store-overlay volume neededForBoot; /nix/var
          # (the persistent Nix DB volume above) must also mount in stage-1 so
          # the boot-time `nix-store --load-db` lands on the persistent volume
          # rather than the tmpfs root it would otherwise shadow — otherwise the
          # system-closure registration is hidden and /run/current-system reads
          # as unregistered on the persistent DB.
          fileSystems."/nix/var".neededForBoot = true;

          users.users.${username} = {
            isNormalUser = true;
            uid = guestUid;
            extraGroups = [ "wheel" ];
            shell = pkgs.bash;
            # SSH from the host into the VM uses these keys over VSOCK.
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBgsFjvY/ARgqDyf8kikQXPOaH7or10sTA2jsgR+vWNk sam@dev-vm"
            ];
          };
          users.users.root.hashedPassword = "!";
          security.sudo.wheelNeedsPassword = false;

          services.openssh.enable = true;

          # On a fresh /home volume nothing under it exists yet, and tmpfiles
          # creates implicit parents as root — so own /home/sam and the
          # home-manager profile chain explicitly (HM's profile lives under
          # ~/.local/state/nix/profiles), plus ~/repos, where shells and sesh
          # start. Everything else under home is created
          # lazily by the user/tools and persists in the volume.
          systemd.tmpfiles.rules = [
            "d /home/${username}                            0700 ${username} users -"
            "d /home/${username}/.local                     0755 ${username} users -"
            "d /home/${username}/.local/state               0755 ${username} users -"
            "d /home/${username}/.local/state/nix           0755 ${username} users -"
            "d /home/${username}/.local/state/nix/profiles  0755 ${username} users -"
            # nvim's log dir. Without it, a Neovim that logs in the guest
            # (notably the headless `--server`/`--remote-send` clients, which
            # skip the startup that would create it) falls back to writing a
            # `.nvimlog` in its cwd — littering repos. Pre-creating it keeps
            # the log at ~/.local/state/nvim/log instead.
            "d /home/${username}/.local/state/nvim          0755 ${username} users -"
            "d /home/${username}/repos                       0755 ${username} users -"
          ];

          networking.useDHCP = lib.mkDefault true;
          # No guest firewall: the VM sits on a host-only bridge with
          # outbound-only NAT and no port forwards, so nothing off the host
          # can reach it. The firewall would only block host→VM access to dev
          # servers (e.g. a web server on 0.0.0.0 reached from host Firefox).
          networking.firewall.enable = false;

          nix.settings.build-dir = "/nix/.rw-store/builds";

          # Scheduled GC to bound the store overlay. The keep-outputs/
          # keep-derivations options are passed here rather than set globally,
          # so they apply ONLY to this weekly job: it reclaims old generations
          # and genuinely-unreachable paths but spares the build-time deps of
          # rooted outputs (the large ZK/Rust/Lean toolchains). A manual
          # `nix-collect-garbage -d` keeps neither (nix.conf defaults), so it's
          # the aggressive full reclaim with no extra flags.
          nix.gc = {
            automatic = true;
            dates = "weekly";
            options = "--delete-older-than 14d --option keep-outputs true --option keep-derivations true";
          };

          # A new base image can omit paths recorded in the persistent Nix DB;
          # resetting the overlay can also leave stale entries. Prune them so
          # Nix re-realises missing paths instead of treating them as valid.
          # Stat-only: no --check-contents (no re-hashing) and no --repair (no
          # rebuild). Runs after the daemon so it never gates shell readiness —
          # the heal window only matters right after one of those rare events.
          systemd.services.nix-db-selfheal = {
            description = "Prune Nix DB entries whose store paths vanished";
            after = [ "nix-daemon.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${config.nix.package.out}/bin/nix-store --verify";
            };
          };

          # GH_TOKEN (gh api), NIX_CONFIG (private flake-input access-tokens),
          # BENCHER_API_KEY (bencher CLI), and the AWS_* keys are forwarded
          # per-session over ssh from the host, which holds the sops-decrypted
          # values; the VM stores no copy. The AWS pair carried here is the
          # READ-ONLY key (terraform plan / describe only) — the ssh-dev-vm
          # wrapper sends that and never the host's write pair (see
          # home/modules/gui.nix, home/profiles/desktop.nix).
          services.openssh.settings.AcceptEnv = [
            "GH_TOKEN"
            "NIX_CONFIG"
            "BENCHER_API_KEY"
            "AWS_ACCESS_KEY_ID"
            "AWS_SECRET_ACCESS_KEY"
          ];

          environment.systemPackages = with pkgs; [
            git
            jq
            # Ghostty's terminfo entry only (not the GUI terminal), so the
            # xterm-ghostty TERM forwarded over ssh from the host terminal is
            # understood here — otherwise less/git-pager/vim report "terminal
            # not fully functional". From unstable to match the host's ghostty
            # (the host build reuses the same terminfo package).
            vmPkgs-unstable.ghostty.terminfo
          ];
        };
    };
}
