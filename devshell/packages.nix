{
  pkgs,
  pkgs-legacy,
  pyenv,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  lib = pkgs.lib;
  versionUtils = pkgs.callPackage ./version_utils.nix { inherit pkgs-legacy; };
  pythonVerConfig = versionUtils.pythonVerConfig;
  curVer = pythonVerConfig.curVer;
  leastVer = pythonVerConfig.minSupportVer;
  drvs = (pkgs.callPackage ./_drvs.nix { inherit pkgs-legacy; });
in
[ pyenv ]
++ (with drvs; [
  cmake
])
++ lib.optionals (system == "x86_64-linux") (
  with drvs;
  [
    sde
  ]
)
++ lib.optionals (system != "aarch64-darwin") (
  with drvs;
  [
    bloaty
    gdb
    pax-utils
    triton-llvm
    valgrind
  ]
)
