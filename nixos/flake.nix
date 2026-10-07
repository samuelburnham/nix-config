{
  description = "NixOS flake config";

  # Binary cache for the NixOS systems and standalone home/nvim outputs,
  # populated by .github/workflows/cache.yml on pushes to `main`. Nix
  # only honours these for trusted users, and prompts before using them unless
  # invoked with --accept-flake-config; the cloud boxes also register the
  # cache in the daemon config, which covers untrusted logins.
  nixConfig = {
    extra-substituters = [ "https://samuelburnham.cachix.org" ];
    extra-trusted-public-keys = [
      "samuelburnham.cachix.org-1:mrT2yCIiV8eYDgsCslfpE0FCPyEoi4GZy3Vv9htiQeU="
    ];
  };

  inputs = {
    # NixOS official package source, using the nixos-26.05 branch
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Tracks master for fast-moving leaf packages (e.g. claude-code) that
    # should update independently of the unstable channel
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # worktrunk moves fast — features like first-class alias dispatch only
    # landed in 0.39 and nixpkgs lags (currently 0.37). Track upstream main
    # so `nix flake update worktrunk` always pulls the latest.
    worktrunk = {
      url = "github:max-sixty/worktrunk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixpkgs-unstable lags the hyprshell release cycle; fzf-style matching
    # for desktop-file exec fields landed in 4.10.1 and isn't in unstable yet.
    # Track upstream directly; `nix flake update hyprshell` pulls the latest.
    hyprshell = {
      url = "github:H3rmt/hyprshell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    microvm = {
      # Pinned to PR #493, which replaces the `socat -T2` notify relay with a
      # proxy that doesn't stall: cloud-hypervisor never propagates systemd's
      # half-close on the vsock notify socket, so socat waited out its 2s
      # timeout on every sd_notify — serializing the dev VM's boot to ~30-50s
      # (issue #474). Pinned to an exact rev because the PR branch is a moving
      # ref that gets force-pushed; an earlier head built against nixpkgs 26.05
      # failed the guest's initrd switch-root. Revert to
      # "github:microvm-nix/microvm.nix" once merged.
      url = "git+https://github.com/microvm-nix/microvm.nix?ref=refs/pull/493/head&rev=396f5f28dae959f0a66fed7b2fc2d09b74cc69e6";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Neovim flake — drives the standalone nvim package + the in-VM editor.
    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Bencher CLI — continuous-benchmarking client, not in nixpkgs. Pinned to a
    # release tag and built from upstream's flake; `nix flake update bencher`
    # bumps it. Built from source (no upstream binary cache).
    bencher = {
      url = "github:bencherdev/bencher/v0.6.8";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # tmux-assistant-resurrect — persists AI-assistant session IDs across tmux
    # restarts/reboots so tmux-resurrect can relaunch each pane's exact
    # conversation. A plain (non-flake) repo of shell + jq scripts, wired in
    # declaratively rather than via its TPM installer: base.nix points
    # resurrect's save/restore hooks at its scripts, and claude.nix registers
    # its SessionStart/End tracking hooks. Pinned via flake.lock; bump with
    # `nix flake update tmux-assistant-resurrect`.
    tmux-assistant-resurrect = {
      url = "github:timvw/tmux-assistant-resurrect";
      flake = false;
    };

    # Neovim plugins tracked from upstream main.
    auto-dark-mode = {
      url = "github:f-person/auto-dark-mode.nvim";
      flake = false;
    };
    direnv-nvim = {
      url = "github:actionshrimp/direnv.nvim";
      flake = false;
    };

  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-master,
      home-manager,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      perSystem =
        { system, pkgs, ... }:
        let
          pkgs-unstable = import nixpkgs-unstable { inherit system; };
          # Standalone nvim — same nvf config used inside the dev microvm
          # and anywhere `nix run github:samuelburnham/dotfiles?dir=nixos#nvim`
          # is invoked.
          customNeovim =
            (inputs.nvf.lib.neovimConfiguration {
              inherit pkgs;
              extraSpecialArgs = {
                inherit inputs pkgs-unstable;
                # nvf's neovimConfiguration overrides the `inputs` specialArg
                # with its own flake's inputs, so our inputs (the nvim plugin
                # sources used in nvim.nix) reach the module under a separate
                # key it won't clobber.
                flakeInputs = inputs;
              };
              modules = [
                ./home/modules/nvim.nix
              ];
            }).neovim;
        in
        {
          # `nix fmt` entry point. nixfmt-tree = treefmt pre-configured with
          # nixfmt (RFC 166), respects .gitignore, caches per-file, parallel.
          formatter = pkgs.nixfmt-tree;

          # Push access to the cache declared in nixConfig above, scoped to
          # this flake: a devshell is per-flake, so the token is present for
          # `nix develop` on this checkout and nowhere else, and cachix stays
          # out of every profile.
          #
          # Host-only in practice — /run/secrets does not exist in the dev
          # microvm, which pulls from the cache but is deliberately given
          # nothing that can write to it. Silent when the secret is absent;
          # cachix reports its own missing-token error if a push is attempted.
          #
          # Read at shell entry rather than eval, so the token never reaches
          # the Nix store. cachix keys its auth token globally rather than per
          # cache (Config.authToken), hence one secret named per cache.
          devShells.default = pkgs.mkShell {
            packages = [ pkgs.cachix ];
            shellHook = ''
              secret=/run/secrets/cachix-token-samuelburnham
              [ -r "$secret" ] && export CACHIX_AUTH_TOKEN="$(cat "$secret")"
              unset secret
            '';
          };

          packages.nvim = customNeovim;
          packages.default = customNeovim;

          # Surface the HM activation derivation as a package + runnable app
          # so `nix build .#sam` and `nix run .#sam` work without needing a
          # home-manager CLI install on the target.
          packages.sam = self.homeConfigurations.sam.activationPackage;

          # Root-owned Claude deny policy for non-NixOS targets (the Ubuntu
          # box), which can't use environment.etc. The box has sudo, so
          # provisioning installs it under root out of band — the per-user
          # settings only carry it as a best-effort fallback. Install with:
          #   sudo install -Dm0444 -o root -g root \
          #     "$(nix build --no-link --print-out-paths \
          #        'github:samuelburnham/dotfiles?dir=nixos#claude-managed-settings')" \
          #     /etc/claude-code/managed-settings.json
          packages.claude-managed-settings =
            (pkgs.formats.json { }).generate "claude-managed-settings.json" {
              permissions.deny = import ./common/claude-deny-list.nix;
            };

          apps.sam = {
            type = "app";
            program = "${self.homeConfigurations.sam.activationPackage}/activate";
          };
        };

      # nixosConfigurations / homeConfigurations are flake-level outputs, not
      # per-system, so they live in `flake` rather than `perSystem`. Shared
      # derivations (pkgs-unstable, pkgs-master, homeManagerModule) stay in
      # this `let` since they're only consumed here.
      flake =
        let
          system = "x86_64-linux";
          # Single source of truth for the primary user's login name.
          # Threaded through specialArgs (NixOS) and extraSpecialArgs
          # (home-manager) so every module derives paths and user-account
          # settings from it, on NixOS hosts and the standalone Ubuntu
          # config alike.
          username = "sam";
          pkgs-unstable = import nixpkgs-unstable { inherit system; };
          pkgs-master = import nixpkgs-master {
            inherit system;
            config.allowUnfree = true;
          };

          # Shared home-manager module config used by all hosts
          homeManagerModule = hostHome: {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {
              inherit
                inputs
                pkgs-unstable
                pkgs-master
                username
                ;
            };
            home-manager.users.${username} = hostHome;
            home-manager.backupFileExtension = "bak";
          };
        in
        {
          nixosConfigurations = {
            # Desktop — AMD, Gigabyte B650I
            nixos = nixpkgs.lib.nixosSystem {
              inherit system;
              specialArgs = { inherit inputs pkgs-unstable username; };
              modules = [
                ./hosts/desktop/default.nix
                home-manager.nixosModules.home-manager
                (homeManagerModule ./home/profiles/desktop.nix)
              ];
            };

            # Laptop — Intel, MSI
            nixbook = nixpkgs.lib.nixosSystem {
              inherit system;
              specialArgs = { inherit inputs pkgs-unstable username; };
              modules = [
                ./hosts/laptop/default.nix
                home-manager.nixosModules.home-manager
                (homeManagerModule ./home/profiles/laptop.nix)
              ];
            };
          };

          # Standalone home-manager — for non-NixOS machines where we install
          # Nix and activate HM without a NixOS system layer (e.g. Ubuntu AMI
          # provisioned via terraform-server, where `sam` is a seeded login
          # alongside the AMI's default `ubuntu` user). Activate on the
          # target with:
          #   nix run github:samuelburnham/dotfiles?dir=nixos#sam
          homeConfigurations.sam = home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
            extraSpecialArgs = {
              inherit
                inputs
                pkgs-unstable
                pkgs-master
                username
                ;
            };
            modules = [ ./home/profiles/ubuntu.nix ];
          };
        };
    };
}
