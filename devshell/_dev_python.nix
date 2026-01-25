{
  pkgs,
  pyenv_with_site_packages,
  debuggable_python,
  ver,
  useNoGIL,
  ...
}:
pkgs.stdenv.mkDerivation {
  pname = "dev_python3." + (builtins.toString ver) + (if useNoGIL then "FreeThreading" else "");
  version = debuggable_python.version;
  unpackPhase = ":";
  src = "./.";
  buildPhase = ":";
  installPhase =
    let
      libSuffix = (builtins.toString ver) + (if useNoGIL then "t" else "");
    in
    ''
      src1=${pyenv_with_site_packages}
      src2=${debuggable_python}
      ${pkgs.rsync}/bin/rsync -a "$src2"/ "$out"/

      chmod -R 755 $out

      src1_lib="$src1/lib/python3.${libSuffix}/site-packages"
      out_lib="$out/lib/python3.${libSuffix}/site-packages"

      for item in "$src1_lib"/*; do
          name=$(basename "$item")
          target="$out_lib/$name"

          if [ ! -e "$target" ]; then
              ln -s "$item" "$target"
              echo "Created symlink: $target -> $item"
          fi
      done
    '';
}
