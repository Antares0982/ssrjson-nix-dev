{
  description = "ssrjson flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-legacy.url = "github:NixOS/nixpkgs/nixos-25.05";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-legacy,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
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
      packages = {
        x86_64-linux.sde = (import nixpkgs { system = "x86_64-linux"; }).callPackage ./devshell/sde.nix { };
      };
      devShells = forAllSystems (
        pkgs:
        let
          pkgs-legacy = import nixpkgs-legacy { inherit (pkgs.stdenv.hostPlatform) system; };
          versionUtils = pkgs.callPackage ./devshell/version_utils.nix { inherit pkgs-legacy; };
          mkVenv =
            (pkgs.callPackage ./devshell/uv_workspace.nix {
              inherit uv2nix pyproject-nix pyproject-build-systems;
            }).mkVenv;
          _drvs = pkgs.callPackage ./devshell/_drvs.nix { inherit pkgs-legacy mkVenv; };
          pythonVerConfig = versionUtils.pythonVerConfig;
          pyVerToPkgs = versionUtils.pyVerToPkgs;
          curVer = pythonVerConfig.curVer;
          leastVer = pythonVerConfig.minSupportVer;
          leastNoGILVer = pythonVerConfig.minSupportNoGILVer;
          getPyEnv = ver: builtins.elemAt _drvs.pyenvs (ver - leastVer);
          getPyEnvNoGIL = ver: builtins.elemAt _drvs.pyenvs_no_gil (ver - leastNoGILVer);
          getUsingPython = ver: builtins.elemAt _drvs.using_pythons (ver - leastVer);
          getUsingPythonNoGIL = ver: builtins.elemAt _drvs.using_pythons_no_gil (ver - leastNoGILVer);
          getShellAndHook =
            { ver, useNoGIL }:
            let
              pyenv = if useNoGIL then getPyEnvNoGIL ver else getPyEnv ver;
              using_python = if useNoGIL then getUsingPythonNoGIL ver else getUsingPython ver;
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
                (mkVenv {
                  python = builtins.getAttr ("python3" + (toString ver)) (pyVerToPkgs ver);
                  group = "build";
                })
              ]
              ++ (with pkgs; [
                cmake
                clang
              ]);
              hardeningDisable = [ "fortify" ];
            };
          };
          verToNoGILBuildEnvDef = ver: {
            name = "buildenv-py3" + (toString ver) + "t";
            value = pkgs.mkShell {
              buildInputs = [
                (mkVenv {
                  python = builtins.getAttr ("python3" + (toString ver) + "FreeThreading") (pyVerToPkgs ver);
                  group = "build";
                })
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
          benchmarkPy = mkVenv {
            python = builtins.getAttr ("python3" + (toString curVer)) (pyVerToPkgs curVer);
            group = "benchmark";
          };
          verToNoGILDevEnvDef = ver: {
            name = "devenv-py3" + (toString ver) + "t";
            value = mkMyShellNoGIL ver;
          };
        in
        rec {
          default = mkMyShell curVer;
          benchmarkenv = pkgs.mkShell {
            packages = [ benchmarkPy ];
          };
        }
        // (builtins.listToAttrs (map verToBuildEnvDef versionUtils.versions))
        // (builtins.listToAttrs (map verToDevEnvDef versionUtils.versions))
        // (builtins.listToAttrs (map verToNoGILBuildEnvDef versionUtils.versionsSupportNoGIL))
        // (builtins.listToAttrs (map verToNoGILDevEnvDef versionUtils.versionsSupportNoGIL))
      );
    };
}
