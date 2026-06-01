{ stdenv, autoPatchelfHook, ... }:
stdenv.mkDerivation {
  name = "intel-sde";
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    mkdir -p $out/share
    cp -r $src/* $out/bin
    runHook postInstall
  '';
  phases = [
    "unpackPhase"
    "installPhase"
    "fixupPhase"
  ];
  src = builtins.fetchTarball {
    url = "https://github.com/Antares0982/ssrjson-nix-dev/releases/download/v0.0.0/sde-external-9.48.0-2024-11-25-lin.tar.xz";
    sha256 = "sha256:1z9nd3lfixwm0nyxim7x7vgfkmxxzj608lacqwm983cbw1x2dg04";
  };
}
