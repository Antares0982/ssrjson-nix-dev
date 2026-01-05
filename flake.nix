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
      devShells = forAllSystems (
        pkgs:
        let
          pkgs-legacy = import nixpkgs-legacy { inherit (pkgs.stdenv.hostPlatform) system; };
          versionUtils = pkgs.callPackage ./devshell/version_utils.nix { inherit pkgs-legacy; };
          defaultShell = pkgs.callPackage ./devshell/shell.nix {
            inherit pkgs-legacy;
          };
          _drvs = pkgs.callPackage ./devshell/_drvs.nix { inherit pkgs-legacy; };
          pythonVerConfig = versionUtils.pythonVerConfig;
          curVer = pythonVerConfig.curVer;
          leastVer = pythonVerConfig.minSupportVer;
          verLength = curVer - leastVer;
          mkMyShell =
            { shell, ... }:
            (
              (shell.overrideAttrs {
                shellHook = pkgs.callPackage ./devshell/shellhook.nix {
                  parentShell = shell;
                  inherit pkgs-legacy;
                  inherit (shell) inputDerivation;
                  inherit (_drvs) pyenvs debuggable_py pyenv_nodebug;
                  nix_pyenv_directory = ".nix-devenv";
                  pyenv = builtins.elemAt _drvs.pyenvs verLength;
                  using_python = builtins.elemAt _drvs.using_pythons verLength;
                };
              })
              // {
                super = shell;
              }
            );
          verToBuildEnvDef = ver: {
            name = "buildenv-py3" + (toString ver);
            value = pkgs.mkShell {
              buildInputs = [
                (
                  (builtins.getAttr ("python3" + (toString ver)) (if ver >= 10 then pkgs else pkgs-legacy))
                  .withPackages
                  (
                    pypkgs: with pypkgs; [
                      # this is needed unless `nix build nixpkgs#python314Packages.pip` can run correctly
                      (if ver < 14 then pip else pkgs.callPackage ./devshell/py314-pip.nix { inherit pypkgs; })
                      build
                      pytest
                      pytest-random-order
                    ]
                  )
                )
              ]
              ++ (with pkgs; [
                cmake
                clang
              ]);
              hardeningDisable = [ "fortify" ];
            };
          };
        in
        {
          internal = defaultShell;
          default = mkMyShell { shell = defaultShell; };
        }
        // (builtins.listToAttrs (map verToBuildEnvDef versionUtils.versions))
      );
    };
}
