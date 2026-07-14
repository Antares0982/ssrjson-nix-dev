{
  pkgs,
  pkgs-legacy,
  fetchFromGitHub,
  # uv2nix venv builder, threaded in from flake.nix. Only forced when `pyenvs` /
  # `pyenvs_no_gil` are evaluated (i.e. via the top-level `_drvs` in flake.nix);
  # the `packages.nix` / `shell.nix` call sites only read tool derivations and
  # never force the pyenvs, so a `null` default keeps those callPackage calls
  # working without threading the uv inputs through them.
  mkVenv ? null,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  lib = pkgs.lib;
  versionUtils = pkgs.callPackage ./version_utils.nix { inherit pkgs-legacy; };
  pythonVerConfig = versionUtils.pythonVerConfig;
  pyVerToPkgs = versionUtils.pyVerToPkgs;
  maxSupportVer = pythonVerConfig.maxSupportVer;
  minSupportVer = pythonVerConfig.minSupportVer;
  minSupportNoGILVer = pythonVerConfig.minSupportNoGILVer;
  curVer = pythonVerConfig.curVer;
  supportedVers = builtins.genList (x: minSupportVer + x) (maxSupportVer - minSupportVer + 1);
  supportedVersNoGIL = builtins.genList (x: minSupportNoGILVer + x) (
    maxSupportVer - minSupportNoGILVer + 1
  );
  using_pythons_map =
    { py, curPkgs, ... }:
    let
      verInt = lib.strings.toInt py.sourceVersion.minor;
      startsWith =
        prefix: str:
        let
          prefixLength = builtins.stringLength prefix;
          strLength = builtins.stringLength str;
        in
        # Check if the string is long enough to contain the prefix
        # and if the substring matches the prefix
        strLength >= prefixLength && builtins.substring 0 prefixLength str == prefix;
      x = (
        py.override {
          self = x;
          packageOverrides = curPkgs.callPackage ./py_overrides.nix {
            inherit
              verInt
              curVer
              curPkgs
              pkgs-legacy
              ;
          };
        }
      );
    in
    x;
  using_pythons = (
    builtins.map using_pythons_map (
      builtins.map (supportedVer: rec {
        curPkgs = pyVerToPkgs supportedVer;
        py = (builtins.getAttr ("python3" + (builtins.toString supportedVer)) (curPkgs));
      }) supportedVers
    )
  );
  using_pythons_no_gil = (
    builtins.map using_pythons_map (
      builtins.map (supportedVer: rec {
        curPkgs = pyVerToPkgs supportedVer;
        py = (
          builtins.getAttr (
            "python3"
            + (builtins.toString supportedVer)
            + lib.optionalString (supportedVer >= minSupportNoGILVer) "FreeThreading"
          ) curPkgs
        );
      }) supportedVersNoGIL
    )
  );
  # Build the "original" python env from the uv2nix "dev" dependency-group
  # instead of `withPackages` (which pulls from nixpkgs and breaks on updates).
  # Re-attach the interpreter passthru attrs consumed downstream
  # (dev-env.nix / shellhook.nix / _dev_python.nix) so the swap is transparent.
  mkDevVenv =
    interp:
    (mkVenv {
      python = interp;
      group = "dev";
    })
    // {
      inherit (interp)
        executable
        sitePackages
        libPrefix
        sourceVersion
        ;
    };
  pyenvs = builtins.map mkDevVenv using_pythons;
  pyenvs_no_gil = builtins.map mkDevVenv using_pythons_no_gil;
  debuggable_py = builtins.map (
    py:
    if system == "x86_64-linux" then
      (pyVerToPkgs (lib.strings.toInt py.sourceVersion.minor)).enableDebugging py
    else
      py
  ) using_pythons;
  debuggable_py_no_gil = builtins.map (
    py:
    if system == "x86_64-linux" then
      pkgs.enableDebugging (py.override { stdenv = pkgs.clangStdenv; })
    else
      py
  ) using_pythons_no_gil;
  sde = pkgs.callPackage ./sde.nix { };
  llvmDbg = pkgs.enableDebugging pkgs.llvmPackages.libllvm;
in
{
  inherit pyenvs; # list
  inherit pyenvs_no_gil; # list
  inherit debuggable_py; # list
  inherit debuggable_py_no_gil; # list
  inherit using_pythons; # list
  inherit using_pythons_no_gil; # list
  inherit llvmDbg;
  inherit (pkgs)
    cmake
    ;
}
// lib.optionalAttrs (system == "x86_64-linux") {
  inherit sde;
}
// lib.optionalAttrs (system != "aarch64-darwin") {
  inherit (pkgs)
    bloaty # binary size profiler
    gdb
    pax-utils # lddtree
    valgrind # memory profiler
    ;
}
