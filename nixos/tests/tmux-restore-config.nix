# nix eval --impure --json --file nixos/tests/tmux-restore-config.nix
let
  flake = builtins.getFlake (toString ../.);
  home = flake.nixosConfigurations.nixos.config.home-manager.users.sam;
  package =
    name:
    toString (
      builtins.head (
        builtins.filter (p: (p.pname or (p.name or "")) == name) home.home.packages
      )
    );
in
{
  tmux = toString home.programs.tmux.package;
  sesh = package "sesh";
  order = package "tmux-session-order";
  resume = package "assistant-resume";
  hooks = (builtins.elemAt home.programs.tmux.plugins 1).extraConfig;
  resurrect = toString (builtins.elemAt home.programs.tmux.plugins 1).plugin;
  continuum = toString (builtins.elemAt home.programs.tmux.plugins 2).plugin;
}
