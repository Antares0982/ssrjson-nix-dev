{
  lib,
  system,
  callPackage,
  pkgs-legacy,
  verInt, # building python version
  curVer, # default version of development
  orjsonDebug ? false,
  ...
}:
let
  makeNewPackages =
    s: f: c:
    builtins.mapAttrs (name: value: if c value then f name else value) s;
  fakeCond =
    value:
    builtins.isAttrs value
    && builtins.hasAttr "pname" value
    && builtins.hasAttr "version" value
    && builtins.hasAttr "overridePythonAttrs" value;
in
(
  self: super:
  let
    noCheckPackage = (
      name:
      super.${name}.overridePythonAttrs {
        doCheck = false;
      }
    );
    noCheckPackages = lst: lib.genAttrs lst noCheckPackage;
    orjsonSimple = callPackage ./orjson_fixed.nix {
      pypkgs = self;
      inherit pkgs-legacy;
      isDebug = orjsonDebug;
    };
    orjsonPypi = callPackage ./orjson-pypi.nix { pypkgs = self; };
  in
  (makeNewPackages super noCheckPackage fakeCond)
  // {
    orjson = if (verInt != curVer || orjsonDebug) then orjsonSimple else orjsonPypi;
    ssrjson-benchmark = callPackage ./ssrjson_benchmark.nix {
      pypkgs = self;
      inherit pkgs-legacy;
    };
  }
)
