# uv2nix wrapper.
#
# Loads the uv workspace at the repo root (pyproject.toml + uv.lock) and exposes
# `mkVenv { python, group }`, which builds a virtual environment containing the
# packages of a single dependency-group ("dev" / "build" / "benchmark").
#
# Packages come from PyPI (pinned by uv.lock) instead of nixpkgs, so updating
# nixpkgs no longer breaks the Python environment.
{
  lib,
  pkgs,
  callPackage,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
  ...
}:
let
  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ../.; };

  # Python versions above this have no buildable numpy yet (from PyPI). Mirrors
  # the original `ver <= latestWheelBuildableVer` gate. Gated in Nix by integer
  # minor version rather than a PEP 508 marker; see pyproject.toml for why.
  latestWheelBuildableVer = (lib.importJSON ./pyver.json).latestWheelBuildableVer;

  # Overlay of the workspace's packages, resolved from uv.lock. Prefer wheels
  # (that is the whole point: avoid building from source where possible).
  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  # Same overlay resolved from sdists, used to pull individual packages that
  # have no usable wheel for our interpreters (see psutil below).
  sdistOverlay = workspace.mkPyprojectOverlay {
    sourcePreference = "sdist";
  };

  # Fixups for packages that may be built from sdist. ssrjson-benchmark ships
  # manylinux wheels for the versions we use (so this is normally a no-op), but
  # keep the cmake/setuptools build inputs in case a wheel is unavailable for a
  # given interpreter and it falls back to building the native extension.
  pyprojectOverrides = final: prev: {
    ssrjson-benchmark = prev.ssrjson-benchmark.overrideAttrs (old: {
      nativeBuildInputs =
        (old.nativeBuildInputs or [ ])
        ++ (final.resolveBuildSystem { setuptools = [ ]; })
        ++ [ pkgs.cmake ];
    });

    # psutil only publishes free-threaded wheels up to cp314t; for every other
    # free-threaded interpreter (e.g. cp315t) it falls back to its cp36-abi3
    # wheel, which uv refuses on a free-threaded build because the stable ABI
    # requires the GIL. There is thus no usable wheel on free-threaded 3.15+,
    # so build psutil from its sdist (a small C extension) instead. The sdist
    # does not declare setuptools in build-system.requires, so add it here.
    psutil = (sdistOverlay final prev).psutil.overrideAttrs (old: {
      nativeBuildInputs =
        (old.nativeBuildInputs or [ ]) ++ (final.resolveBuildSystem { setuptools = [ ]; });
    });
  };

  # Build a python package set for a specific interpreter, then a venv holding
  # the requested dependency-group.
  mkVenv =
    {
      python,
      group,
    }:
    let
      pythonSet =
        (callPackage pyproject-nix.build.packages {
          inherit python;
        }).overrideScope
          (
            lib.composeManyExtensions [
              pyproject-build-systems.overlays.default
              overlay
              pyprojectOverrides
            ]
          );
      # Drop numpy for versions with no buildable numpy: pick the `-nonumpy`
      # group variant. Only "dev"/"build" have such a variant.
      pyMinor = lib.toInt python.sourceVersion.minor;
      effectiveGroup =
        if (group == "dev" || group == "build") && pyMinor > latestWheelBuildableVer then
          "${group}-nonumpy"
        else
          group;
      # deps.groups is `{ <root-package> = [ <all group names> ]; }`; rewrite it
      # to select only `effectiveGroup` without hardcoding the root package name.
      depSpec = builtins.mapAttrs (_: _: [ effectiveGroup ]) workspace.deps.groups;
    in
    pythonSet.mkVirtualEnv "ssrjson-${effectiveGroup}-env" depSpec;
in
{
  inherit mkVenv;
}
