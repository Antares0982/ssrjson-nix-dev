{
  pypkgs,
  pkgs,
  pkgs-legacy,
  lib,
  fetchPypi,
  cmake,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  minorVer = lib.strings.toInt pypkgs.python.sourceVersion.minor;
  versionUtils = pkgs.callPackage ./version_utils.nix { inherit pkgs-legacy; };
  pythonVerConfig = versionUtils.pythonVerConfig;
  useNixpkgsUnstable = (minorVer > pythonVerConfig.latestUseStableNixpkgsVer);
in
pypkgs.buildPythonPackage rec {
  pname = "ssrjson_benchmark";
  version = "0.0.11";
  pyproject = true;

  disabled = pypkgs.pythonOlder "3.10";

  # src = pkgs.fetchFromGitHub {
  #   owner = "Nambers";
  #   repo = "ssrJSON-benchmark";
  #   rev = "eeefc6e757ef66eebf031d99dd09576532439043";
  #   sha256 = "sha256-0bCcVMd20Mm3kem7VuBDO1OaO3GnfT92OjDEvMQyC7w=";
  # };

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-dtc17JzBGgwDFhBUYscT2GCC+jWNP4D/MbVzNpejN90=";
  };

  build-system = with pypkgs; [ setuptools ];

  nativeBuildInputs = with pypkgs; [
    cmake
  ];

  dependencies =
    with pypkgs;
    [
      msgspec
      orjson
      ujson
      pydantic
    ]
    ++ (lib.optionals (system == "x86_64-linux") (
      with pypkgs;
      [
        matplotlib
        psutil
        reportlab
        svglib
      ]
    ));

  configurePhase = ":";

  pythonRuntimeDepsCheckHook = ":";
}
