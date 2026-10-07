# Commands Claude Code must never run on the user's behalf. Enforced
# immutably through the root-owned /etc/claude-code/managed-settings.json
# (see claude-managed-settings.nix), and mirrored into the per-user
# ~/.claude/settings.json as a best-effort fallback on hosts that don't
# deploy the managed file (the standalone Ubuntu box). Destroying/applying
# infrastructure and driving cloud CLIs are human-only actions: a compromised
# session must not be able to touch live cloud state, and — because these
# live in a file the session's user cannot write — it cannot lift the rule
# by rewriting its own settings.
[
  "Bash(terraform apply:*)"
  "Bash(terraform destroy:*)"
  "Bash(aws:*)"
]
