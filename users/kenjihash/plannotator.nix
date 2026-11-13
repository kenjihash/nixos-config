{ lib, stdenv, stdenvNoCC, fetchurl, autoPatchelfHook, openssl }:

let
  version = "0.28.62";
  # Install the pinned binary without upstream hooks, skills, or sidecars.
  assets = {
    aarch64-linux = {
      name = "linux-arm64";
      sha256 = "3d0f58057ed0efd787b126d29f2c57d004836526e234e010a78e9fa7b95e89c6";
    };
    x86_64-linux = {
      name = "linux-x64";
      sha256 = "067f5c59da36b60bdce330d28eb29484f5f409e6028978b62061883296820fb0";
    };
    aarch64-darwin = {
      name = "darwin-arm64";
      sha256 = "e373925633fe9986e898bb53dffc26a0e664511163e2646c1e2655fbf65da9ca";
    };
    x86_64-darwin = {
      name = "darwin-x64";
      sha256 = "ac0207f9d966bf1b9c2b295c3df311038efea28d194ece0db83932c4e0b310f3";
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
