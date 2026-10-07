# Nix config

NixOS configurations for the desktop and laptop, the desktop's dev microVM,
and a standalone Home Manager environment for Ubuntu live in this flake.

The Emacs configuration is preserved on the `emacs` branch as `init.el`.

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

Pushes to `main` run the `cache` workflow, which builds these
configurations in parallel and uploads their closures to `samuelburnham.cachix.org`:

- `nixosConfigurations.nixos.config.system.build.toplevel`: desktop and dev microVM.
- `nixosConfigurations.nixbook.config.system.build.toplevel`: laptop.
- `sam`: standalone home-manager environment, including the `nvim` package.

The workflow uses a repository secret named `CACHIX_AUTH_TOKEN` with write access
to the cache. Cachix uploads completed derivations during the build, and a final
push covers the full output closure. The workflow can also be started manually
from GitHub Actions.

Builds use the committed lockfile and do not activate either system or restart the
microVM. The separate `check` workflow evaluates the flake on pull requests into
`main` and pushes to `main`. It also runs `argumentcomputer/ci-workflows`' shared
workflow linter: actionlint, ShellCheck, pinact verification, and zizmor. Actions
must use full commit hashes; pinact verifies their version comments.

Dependabot checks GitHub Actions weekly and opens grouped update PRs for `main`,
with a seven-day cooldown for version updates. GitHub reads
`.github/dependabot.yml` from the default branch, so that file must also reach
`main` to enable the updates.

The cache is declared in `flake.nix`. To build a system using that configuration:

```sh
nix build --accept-flake-config .#nixosConfigurations.nixos.config.system.build.toplevel
```

## Restore /home from backup

**Config comes from nix, state comes from restic.** `git clone` + `nixos-rebuild`
gives a working machine with empty data; restic fills in only what can't be
regenerated. `/home/sam` is backed up daily to the One Touch drive
(`services.restic.backups.onetouch`, repo `/mnt/onetouch/NixOS-restic`).

The backup runs as the dedicated `restic` account with systemd's
`CAP_DAC_READ_SEARCH`, allowing it to read private files without running as root.
Its filesystem exposes the home directory read-only, the backup destination,
and its own credential/cache/runtime directories. Git runs separately as `sam`
in a sandbox that can only read `~/repos`, with no capabilities, host secrets,
network, or host socket access.

Repositories under `~/repos` honor `.gitignore` and `.git/info/exclude`, including
linked worktrees and submodules. Global Git ignore files are not consulted.
Tracked files are retained even when they match ignore rules. Ignored state
such as an untracked `.env` is **not backed up**. Paths that cannot be encoded
safely as Restic exclusion patterns are retained with a journal warning. A
scanner or validation failure prevents backup and pruning.

The exFAT drive uses Sam as its owner and the reserved `restic` group (GID 291)
for backup writes. After rebuilding with changed mount options, safely unmount
and reconnect the drive so the new permissions take effect. A disconnected
drive fails the scheduled run; reconnecting does not automatically retry it.
Start a retry with `sudo systemctl start restic-backups-onetouch` and inspect
both `restic-gitignore-onetouch` and `restic-backups-onetouch` in the journal.

Each successful backup/prune run includes a structural `restic check`.
`restic-onetouch snapshots` and `restic-onetouch check --read-data` also work
interactively; the latter reads the entire repository and should be run
periodically when there is time for a full integrity check.

Home-manager owns most of `~` as `/nix/store` symlinks and recreates them on
activation, so **don't blanket-restore over `~`**: dropping a stale regular file
on top of an HM-managed path causes "would be clobbered" on the next switch.
Restore selectively instead.

### Prerequisites

- The One Touch drive connected.
- The sops age key. It normally lives at `~/.config/sops/age/keys.txt` — which is
  *inside* the backup, so a copy must be kept off-disk, or the restic password
  (below) can't be decrypted and the backup can't be opened.

### Steps

1. Rebuild from the flake first, so home-manager lays down its own dotfiles:
   ```
   mkdir -p ~/repos
   git clone https://github.com/samuelburnham/nix-config.git ~/repos/nix-config
   cd ~/repos/nix-config
   sudo nixos-rebuild switch --flake .#<host>
   ```
2. Get the repo password:
   ```
   sudo cat /run/secrets/restic-password                     # running system
   # fresh machine (secrets not decrypted yet):
   SOPS_AGE_KEY_FILE=/path/to/keys.txt \
     sops -d --extract '["restic-password"]' secrets/secrets.yaml
   ```
3. Mount the backup read-only and cherry-pick state back with the helper script.
   It mounts via FUSE (nothing is staged to disk); rsync only real data from
   another terminal — Documents, repos, `~/.local/share/<app>`, keys, browser
   profiles — and skip anything home-manager owns:
   ```
   export RESTIC_PASSWORD=...       # from step 2, if not on the live system
   ./scripts/restic-restore.sh      # Ctrl-C to unmount when done
   ```
4. On any conflict, delete the restored copy and let `nixos-rebuild switch` win —
   the declarative version is canonical.

### Not covered by this backup

restic only stores `/home/sam`, so these are not restored and must be set up
again: WiFi credentials (`/etc/NetworkManager/system-connections`), Bluetooth
pairings (`/var/lib/bluetooth`), the dev microvm's `home.img` under
`/var/lib/microvms/`, and the excluded `.cache` / Steam / `.local/share/containers`.
