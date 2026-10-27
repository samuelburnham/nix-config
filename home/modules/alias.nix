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

  # Pushes the running system to the cache. The token is read here rather
  # than exported by a shell rc, so it only ever reaches this cachix process.
  # The dev microvm has no /run/secrets and is deliberately unable to push;
  # cachix reports the missing token there.
  cachix-push = pkgs.writeShellApplication {
    name = "cachix-push";
    runtimeInputs = [ pkgs.cachix ];
    text = ''
      secret=/run/secrets/cachix-token-samuelburnham
      if [ -r "$secret" ]; then
        CACHIX_AUTH_TOKEN="$(cat "$secret")"
        export CACHIX_AUTH_TOKEN
      fi
      cachix push samuelburnham /run/current-system
    '';
  };
in
{
  home.packages = [
    rebuild
    cachix-push
  ];
}
