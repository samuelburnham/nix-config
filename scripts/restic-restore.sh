#!/usr/bin/env bash
# Browse backup snapshots through a read-only FUSE mount without staging a copy.
# Bulk recovery uses `restic restore`; see ../docs/backup.md for the recovery steps.
# Ctrl-C unmounts and removes the mountpoint.
set -euo pipefail

export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/mnt/onetouch/NixOS-restic}"
MNT="${1:-$HOME/restic-mount}"

# The configured host supplies the password through SOPS. A recovery session
# can supply RESTIC_PASSWORD_FILE or enter the password at Restic's prompt.
if [ -z "${RESTIC_PASSWORD:-}" ] && [ -z "${RESTIC_PASSWORD_FILE:-}" ] \
   && [ -r /run/secrets/restic-password ]; then
  export RESTIC_PASSWORD_FILE=/run/secrets/restic-password
fi

mkdir -p "$MNT"
trap 'fusermount3 -u "$MNT" 2>/dev/null || fusermount -u "$MNT" 2>/dev/null; rmdir "$MNT" 2>/dev/null || true' EXIT

cat <<EOF
Mounting $RESTIC_REPOSITORY  ->  $MNT  (read-only)

Browse snapshots from another terminal. Copy files to an empty directory for
inspection before putting them back, e.g.:
  rsync -aHAX "$MNT/snapshots/latest/home/sam/Documents/" "$HOME/recovered-documents/"

Browse the other snapshot directories to recover an older version.
For a full home recovery, use restic restore and then activate Home Manager;
see docs/backup.md for the steps.

Press Ctrl-C here to unmount.
EOF

restic mount "$MNT"
