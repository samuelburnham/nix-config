{
  pkgs,
  config,
  ...
}:
let
  # The installed wrapper embeds the checkout path. After relocating it,
  # activate once with an explicit path to regenerate the wrapper:
  #   nixos-rebuild switch --flake /new/path/to/nix-config --sudo
  rebuild = pkgs.writeShellApplication {
    name = "rebuild";
    text = "nixos-rebuild switch --flake ${config.home.homeDirectory}/repos/nix-config --sudo";
  };
in
{
  home.packages = [
    rebuild
  ];
}
