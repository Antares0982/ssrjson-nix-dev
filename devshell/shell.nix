{
  pkgs,
  pkgs-legacy,
  pyenv,
  using_python,
  ...
}:
let
  nix_pyenv_directory = ".nix-devenv";
  drvs = pkgs.callPackage ./_drvs.nix { inherit pkgs-legacy; };
in
(pkgs.mkShell {
  packages = pkgs.callPackage ./packages.nix { inherit pkgs-legacy pyenv; };
  hardeningDisable = [ "fortify" ];
})
