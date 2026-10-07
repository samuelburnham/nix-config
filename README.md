# Nix config

NixOS configurations for the desktop and laptop, the desktop's dev microVM, and
a standalone Home Manager environment for Ubuntu.

## Install

- Run `nix-shell -p vim -p git`

- Run `sudo vim /etc/nixos/configuration.nix` to enable flakes:

```
# /etc/nixos/configuration.nix

# ...
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
# ...
```

- Confirm the settings with `sudo nixos-rebuild switch`

- Clone the repository into `~/repos/nix-config`:

  ```sh
  mkdir -p ~/repos
  git clone https://github.com/samuelburnham/nix-config.git ~/repos/nix-config
  cd ~/repos/nix-config
  ```

- Choose the `nixos` output for the desktop or `nixbook` for the laptop. Review
  the matching `hosts/desktop/hardware-configuration.nix` or
  `hosts/laptop/hardware-configuration.nix` against the machine's generated
  `/etc/nixos/hardware-configuration.nix` before activation.

- Activate the desktop configuration (substitute `nixbook` for the laptop):

  ```sh
  nixos-rebuild switch --flake ~/repos/nix-config#nixos --sudo
  ```

Subsequent updates can use `rebuild`. That command embeds the flake's location;
if the checkout or flake moves, run the explicit command above once to activate
the wrapper with the new path. No `/etc/nixos` symlink is needed.

Sources:
[Enable Nix flakes](https://nixos-and-flakes.thiscute.world/nixos-with-flakes/nixos-with-flakes-enabled#enable-nix-flakes)
[Managing config with git](https://nixos-and-flakes.thiscute.world/nixos-with-flakes/other-useful-tips#managing-the-configuration-with-git)

## CI and binary cache

Pushes to `main` run the `cache` workflow, which builds these configurations in
parallel and uploads their closures to `samuelburnham.cachix.org`:

- `nixosConfigurations.nixos.config.system.build.toplevel`: desktop and dev
  microVM.
- `nixosConfigurations.nixbook.config.system.build.toplevel`: laptop.
- `sam`: standalone home-manager environment, including the `nvim` package.

The workflow uses a repository secret named `CACHIX_AUTH_TOKEN` with write
access to the cache. Cachix uploads completed derivations during the build, and
a final push covers the full output closure. The workflow can also be started
manually from GitHub Actions.

Builds use the committed lockfile and do not activate either system or restart
the microVM. The separate `check` workflow evaluates the flake on pull requests
into `main` and pushes to `main`. It also runs `argumentcomputer/ci-workflows`'
shared workflow linter: actionlint, ShellCheck, pinact verification, and zizmor.
Actions must use full commit hashes; pinact verifies their version comments.

Dependabot checks GitHub Actions weekly and opens grouped update PRs for `main`,
with a seven-day cooldown for version updates. GitHub reads
`.github/dependabot.yml` from the default branch, so that file must also reach
`main` to enable the updates.

The cache is declared in `flake.nix`. To build a system using that
configuration:

```sh
nix build --accept-flake-config .#nixosConfigurations.nixos.config.system.build.toplevel
```

## Backup and recovery

See [the backup guide](docs/backup.md) for backup coverage and recovery instructions.
