#!/usr/bin/env bash
# Browse the NixOS-restic backup read-only and cherry-pick STATE back into ~.
#
# Model: config comes from nix (git clone + nixos-rebuild); restic only holds
# state that can't be regenerated. Rebuild from the flake FIRST so home-manager
# lays down its own dotfile symlinks, then run this and rsync back only real
# data (Documents, repos, ~/.local/share/<app>, keys, browser profiles, ...).
# Don't blanket-restore over ~ — that shadows HM's symlinks with stale files
# and you get "would be clobbered" on the next switch.
#
# This mounts the repo read-only (FUSE — nothing is copied to disk); pick files
# from another terminal. Ctrl-C unmounts and removes the mountpoint.
set -euo pipefail

export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/mnt/onetouch/NixOS-restic}"
MNT="${1:-$HOME/restic-mount}"

# Live system has the password decrypted already. On a fresh machine, decrypt it
# with the saved age key first (see ../README.md) and `export RESTIC_PASSWORD`.
if [ -z "${RESTIC_PASSWORD:-}" ] && [ -z "${RESTIC_PASSWORD_FILE:-}" ] \
   && [ -r /run/secrets/restic-password ]; then
  export RESTIC_PASSWORD_FILE=/run/secrets/restic-password
fi

mkdir -p "$MNT"
trap 'fusermount3 -u "$MNT" 2>/dev/null || fusermount -u "$MNT" 2>/dev/null; rmdir "$MNT" 2>/dev/null || true' EXIT

cat <<EOF
Mounting $RESTIC_REPOSITORY  ->  $MNT  (read-only)

From another terminal, cherry-pick state back, e.g.:
  rsync -aHAX "$MNT/snapshots/latest/home/sam/Documents/"  ~/Documents/
  rsync -aHAX "$MNT/snapshots/latest/home/sam/.gnupg/"     ~/.gnupg/

Skip anything home-manager owns — its dotfiles rebuild from the flake. If a
restored file conflicts with HM on 'switch', delete the restored copy; the
declarative version wins.

Press Ctrl-C here to unmount.
EOF

restic mount "$MNT"
