# Root-owned Claude Code policy at /etc/claude-code/managed-settings.json.
# Claude Code reads this as its highest-precedence settings layer and never
# writes it. Because it lives in /etc (owned by root), the unprivileged user
# Claude runs as — inside the dev microvm, or on the desktop host — cannot
# edit it to lift its own restrictions, unlike ~/.claude/settings.json which
# that user owns and can replace at will. This is where the enforced deny
# policy belongs: a compromised session may tamper with the user settings all
# it likes, but cannot grant itself a permission this file withholds.
#
# Imported into each host's SYSTEM config (the microvm guest and the desktop
# host), not home-manager — /etc is a system, not per-user, concern.
{ pkgs, ... }:
{
  environment.etc."claude-code/managed-settings.json".source =
    (pkgs.formats.json { }).generate "claude-managed-settings.json" {
      permissions.deny = import ./claude-deny-list.nix;
    };
}
