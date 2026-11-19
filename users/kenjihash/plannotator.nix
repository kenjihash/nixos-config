{ lib, stdenv, stdenvNoCC, fetchurl, autoPatchelfHook, openssl }:

let
  version = "0.29.0";
  # Install the pinned binary without upstream hooks, skills, or sidecars.
  assets = {
    aarch64-linux = {
      name = "linux-arm64";
      sha256 = "54086386c8bd6335a133bcc3f9ed28ef4ba861cf072b70cef32d0e1d124829fb";
    };
    x86_64-linux = {
      name = "linux-x64";
      sha256 = "f2c575e7ae219472a45f53adb667ebb6eff13c2d89726d992d1f984a81161391";
    };
    aarch64-darwin = {
      name = "darwin-arm64";
      sha256 = "c383a5ff5338af20ced2c0090926e0ecd6a6019dcdd4112901bbb859e4186c06";
    };
    x86_64-darwin = {
      name = "darwin-x64";
      sha256 = "3d6da648a26887753fc959b547a7654fbe20200de5eb1aea93d839fee79173fa";
    };
  };
  system = stdenvNoCC.hostPlatform.system;
  asset = assets.${system} or (throw "plannotator: no release asset for ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "plannotator";
  inherit version;

  src = fetchurl {
    url = "https://github.com/backnotprop/plannotator/releases/download/v${version}/plannotator-${asset.name}";
    inherit (asset) sha256;
  };

  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ openssl stdenv.cc.cc.lib ];
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  # Bun standalone executables carry their application after the ELF payload.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/plannotator"
    runHook postInstall
  '';

  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    export PLANNOTATOR_DATA_DIR="$TMPDIR/plannotator-check"
    "$out/bin/plannotator" --version | grep -F '${version}'
    runHook postInstallCheck
  '';

  meta = {
    description = "Browser annotation of documents and code reviews";
    homepage = "https://github.com/backnotprop/plannotator";
    license = with lib.licenses; [ mit asl20 ];
    platforms = builtins.attrNames assets;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "plannotator";
  };
}
