# Codex CLI, imported alongside claude.nix in the same profiles rather than
# from base.nix, so it stays out of closures that don't want an agent.
#
# Deliberately thin next to claude.nix: shared context, model defaults, and
# automatic review of sandbox escalation requests. Codex's `rules/` prefix
# allow-lists do not map onto the Claude deny-list in
# common/claude-deny-list.nix, so that policy is not shared here.
{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  # `case` patterns matching each trusted root and everything beneath it.
  trustedPatterns = lib.concatMapStringsSep "|" (r: "${r}|${r}/*") config.programs.codex.trustedRoots;

  codexWrapped = pkgs.writeShellApplication {
    name = "codex";
    runtimeInputs = [
      pkgs.git
      pkgs.jq
    ];
    derivationArgs = {
      inherit (pkgs-unstable.codex) version;
      meta = pkgs-unstable.codex.meta // {
        mainProgram = "codex";
      };
    };
    text = ''
      codex_project_root=$PWD
      if git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        codex_project_root=$git_root
      fi

      # ~/.codex/config.toml is a read-only store symlink, so accepting the
      # TUI's trust prompt fails when it tries to persist the answer. Trust
      # has to be settled here, per launch, for every root a user works in.
      case "$codex_project_root" in
        ${trustedPatterns})
          project_key=$(jq -Rn --arg path "$codex_project_root" '$path')
          # Quoted segments in -c keys are treated literally, so put the
          # dynamic path in the projects table value instead.
          exec ${pkgs-unstable.codex}/bin/codex \
            -c "projects={$project_key={trust_level=\"trusted\"}}" "$@"
          ;;
        *)
          exec ${pkgs-unstable.codex}/bin/codex "$@"
          ;;
      esac
    '';
  };
in
{
  options.programs.codex.trustedRoots = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ "/home/sam/repos" ];
    description = ''
      Directories (and everything beneath them) that the codex wrapper marks
      as trusted projects at launch, so Codex loads their project-local
      config without prompting. Anything else gets the interactive trust
      prompt, whose answer cannot be persisted because config.toml is
      store-backed.
    '';
  };

  config.programs.codex = {
    enable = true;
    package = codexWrapped;
    settings = {
      # config.toml is a store symlink, so `/model` in the TUI cannot save a
      # default; it has to be declared here.
      model = "gpt-6-astra";
      model_reasoning_effort = "max";
      approvals_reviewer = "auto_review";
      features.apps = false;
      tui.status_line = [
        "model-with-reasoning"
        "current-dir"
        "approval-mode"
        "context-used"
        "five-hour-limit"
        "weekly-limit"
        "codex-version"
        "context-window-size"
        "task-progress"
      ];
    };
    # Written to ~/.codex/AGENTS.md. Shared with claude.nix's CLAUDE.md; see
    # agent-context.nix for what belongs here versus in an agent's own module.
    context = (import ./agent-context.nix) + ''

      # Codex configuration

      All Codex configuration changes must be made declaratively in
      `~/repos/nix-config/home/modules/codex.nix`. Never modify
      `~/.codex/config.toml` directly.
    '';
  };
}
