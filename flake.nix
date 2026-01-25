{
  description = "ssrjson flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-legacy.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-legacy,
      ...
    }:
    let
      forAllSystems =
        function:
        nixpkgs.lib.genAttrs
          [
            "x86_64-linux"
            "aarch64-linux"
            "aarch64-darwin"
          ]
          (
            system:
            function (
              import nixpkgs {
                inherit system;
              }
            )
          );

    in
    {
      ssrjson-nixpkgs = nixpkgs;
      ssrjson-nixpkgs-legacy = nixpkgs-legacy;
      devShells = forAllSystems (
        pkgs:
        let
          pkgs-legacy = import nixpkgs-legacy { inherit (pkgs.stdenv.hostPlatform) system; };
          versionUtils = pkgs.callPackage ./devshell/version_utils.nix { inherit pkgs-legacy; };
          _drvs = pkgs.callPackage ./devshell/_drvs.nix { inherit pkgs-legacy; };
          pythonVerConfig = versionUtils.pythonVerConfig;
          curVer = pythonVerConfig.curVer;
          leastVer = pythonVerConfig.minSupportVer;
          getPyEnv = ver: builtins.elemAt _drvs.pyenvs (ver - leastVer);
          getUsingPython = ver: builtins.elemAt _drvs.using_pythons (ver - leastVer);
          getShellAndHook =
            { ver, useNoGIL }:
            let
              pyenv = getPyEnv ver;
              using_python = getUsingPython ver;
              shell = pkgs.callPackage ./devshell/shell.nix {
                inherit pkgs-legacy;
                inherit pyenv using_python;
              };
              shellHook = pkgs.callPackage ./devshell/shellhook.nix {
                parentShell = shell;
                inherit pkgs-legacy;
                inherit (shell) inputDerivation;
                inherit (_drvs) pyenvs pyenvs_no_gil;
                debuggable_py = if useNoGIL then _drvs.debuggable_py_no_gil else _drvs.debuggable_py;
                nix_pyenv_directory = ".nix-devenv";
                inherit pyenv using_python useNoGIL;
              };
              finalShell = shell.overrideAttrs {
                inherit shellHook;
              };
            in
            {
              inherit shell shellHook finalShell;
            };
          mkMyShell =
            selectedVer:
            let
              shellAndHook = getShellAndHook {
                ver = selectedVer;
                useNoGIL = false;
              };
              shell = shellAndHook.shell;
              shellHook = shellAndHook.shellHook;
            in
            shellAndHook.finalShell;
          mkMyShellNoGIL =
            selectedVer:
            let
              shellAndHook = getShellAndHook {
                ver = selectedVer;
                useNoGIL = true;
              };
              shell = shellAndHook.shell;
              shellHook = shellAndHook.shellHook;
            in
            shellAndHook.finalShell;
          verToBuildEnvDef = ver: {
            name = "buildenv-py3" + (toString ver);
            value = pkgs.mkShell {
              buildInputs = [
                ((builtins.getAttr ("python3" + (toString ver)) pkgs).withPackages (
                  pypkgs: with pypkgs; [
                    # this is needed unless `nix build .#ssrjson-nixpkgs.legacyPackages.x86_64-linux.python314Packages.pip` can run correctly
                    (if ver < 14 then pip else pkgs.callPackage ./devshell/py314-pip.nix { inherit pypkgs; })
                    build
                    pytest
                    pytest-random-order
                  ]
                ))
              ]
              ++ (with pkgs; [
                cmake
                clang
              ]);
              hardeningDisable = [ "fortify" ];
            };
          };
          verToNoGILBuildEnvDef = ver: {
            name = "buildenv-py3" + (toString ver) + "-FreeThreading";
            value = pkgs.mkShell {
              buildInputs = [
                ((builtins.getAttr ("python3" + (toString ver) + "FreeThreading") pkgs).withPackages (
                  pypkgs: with pypkgs; [
                    # this is needed unless `nix build .#ssrjson-nixpkgs.legacyPackages.x86_64-linux.python314Packages.pip` can run correctly
                    (if ver < 14 then pip else pkgs.callPackage ./devshell/py314-pip.nix { inherit pypkgs; })
                    build
                    pytest
                    pytest-random-order
                  ]
                ))
              ]
              ++ (with pkgs; [
                cmake
                clang
              ]);
              hardeningDisable = [ "fortify" ];
            };
          };
          verToDevEnvDef = ver: {
            name = "devenv-py3" + (toString ver);
            value = mkMyShell ver;
          };
          verToNoGILDevEnvDef = ver: {
            name = "devenv-py3" + (toString ver) + "-FreeThreading";
            value = mkMyShellNoGIL ver;
          };
        in
        rec {
          default = mkMyShell curVer;
        }
        // (builtins.listToAttrs (map verToBuildEnvDef versionUtils.versions))
        // (builtins.listToAttrs (map verToDevEnvDef versionUtils.versions))
        // (builtins.listToAttrs (map verToNoGILBuildEnvDef versionUtils.versionsSupportNoGIL))
        // (builtins.listToAttrs (map verToNoGILDevEnvDef versionUtils.versionsSupportNoGIL))
      );
    };
}
