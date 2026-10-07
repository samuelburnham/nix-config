# Backup and recovery

Nix rebuilds the system and managed configuration; Restic recovers your data.
The daily backup stores `/home/sam` in `/mnt/onetouch/NixOS-restic`.
Run repository-relative commands from the checkout root.

## Recover files on the working host

Connect the backup drive. `restic-onetouch` supplies the repository and password.
Restore into an empty directory, then inspect and copy back the files you need:

```sh
restic-onetouch snapshots
restic-onetouch restore latest:/home/sam/Documents --target ~/recovered-documents
```

Change `Documents` to the desired path. Replace `latest` with a snapshot ID to
recover an older version. No rebuild is needed for ordinary data files.

For browsing, `./scripts/restic-restore.sh` mounts snapshots read-only. For
larger recoveries, upstream recommends the faster
[`restic restore`](https://restic.readthedocs.io/en/stable/050_restore.html).

## Recover home on a replacement machine

Start with a basic NixOS installation. Use a root session with Sam logged out
and the dev microVM stopped; the destination home should be empty or disposable.

1. Mount the backup drive at `/mnt/onetouch` and make Restic available
   (`nix-shell -p restic sops` if needed). Have the saved Restic password ready.
   If you saved only the age key, decrypt the password from a checkout of this
   repository:

   ```sh
   SOPS_AGE_KEY_FILE=/path/to/saved-age-key.txt \
     sops -d --extract '["restic-password"]' secrets/secrets.yaml
   ```

   Keep the password or age key outside the backup so recovery can start.

2. Restore home directly, entering the password when prompted:

   ```sh
   restic -r /mnt/onetouch/NixOS-restic snapshots
   restic -r /mnt/onetouch/NixOS-restic restore latest:/home/sam --target /home/sam
   ```

   Use the chosen snapshot ID instead of `latest` when recovering an older state.

3. Review the hardware configuration in `/home/sam/repos/nix-config`
   (clone the repository there if absent). Ensure the age key is present at
   `/home/sam/.config/sops/age/keys.txt` before activating secrets. Then rebuild
   the desktop, substituting `nixbook` for the laptop:

   ```sh
   nixos-rebuild switch --flake /home/sam/repos/nix-config#nixos
   ```

Restic preserves symlinks, and Home Manager regenerates its managed links on
activation. Conflicting ordinary files are moved aside with the configured
`.bak` suffix when possible. If activation reports a collision, inspect and
move the conflicting file aside rather than deleting it blindly.

## Not covered by this backup

Only the host's `/home/sam` is covered. WiFi credentials, Bluetooth pairings,
and the microVM's `home.img` are outside this backup. VM-private assistant
conversations and tmux state are therefore not restored; shared repositories
are covered. Exclusions also omit `.cache`, Steam, `.local/share/containers`,
and Git-ignored untracked files in repositories.
