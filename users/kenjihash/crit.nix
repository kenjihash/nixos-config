{ lib, stdenvNoCC, fetchurl }:

let
  version = "0.23.2";
  # Standalone upstream Go binaries, pinned to GitHub's release digests.
  assets = {
    aarch64-linux = {
      name = "linux-arm64";
      sha256 = "fc1cc46624d5573157336e96bc3b93c965cd649eb8168f966b8b93f77c0b4072";
    };
    x86_64-linux = {
      name = "linux-amd64";
      sha256 = "10aa756a3146362be3a349cc8223955e23a1cd6daa0abbb13dd500741f793a90";
    };
    aarch64-darwin = {
      name = "darwin-arm64";
      sha256 = "b97dcfb1c54f301cfba4a1b92edaaa6e9f9a3c0ba5230120aa79f6d8253fbd35";
    };
    x86_64-darwin = {
      name = "darwin-amd64";
      sha256 = "3a3effd5afcd5843feadf1b326deb6271317988089abd027db74addbeb79534e";
    };
  };
  system = stdenvNoCC.hostPlatform.system;
  asset = assets.${system} or (throw "crit: no release asset for ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "crit";
  inherit version;

  src = fetchurl {
    url = "https://github.com/tomasz-tomczyk/crit/releases/download/v${version}/crit-${asset.name}";
    inherit (asset) sha256;
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/crit"
    runHook postInstall
  '';

  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/crit" --version | grep -F 'v${version}'
    runHook postInstallCheck
  '';

  meta = {
    description = "Browser review of Markdown, code diffs, and running apps";
    homepage = "https://github.com/tomasz-tomczyk/crit";
    license = lib.licenses.mit;
    platforms = builtins.attrNames assets;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "crit";
  };
}
