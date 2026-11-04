{ lib, stdenvNoCC, fetchurl, xz }:

let
  version = "1.8.0";
  # Compressed release assets, pinned to GitHub's published SHA-256 digests.
  # Bump these with the version; the self-updater cannot write to /nix/store.
  assets = {
    aarch64-linux = {
      name = "linux-arm64";
      sha256 = "b7429788310dabc3d4dafdc314889011e243a48cbce2d084e0f2581a0882421e";
    };
    x86_64-linux = {
      name = "linux-amd64";
      sha256 = "e3e75116f7323e1d86824ef73a17bfadceafccb5538e3410df8f0b74ac018f95";
    };
    aarch64-darwin = {
      name = "darwin-arm64";
      sha256 = "9d088f85caf73191545ce8125f51aae43187f1896e06616449971675ff91b50f";
    };
    x86_64-darwin = {
      name = "darwin-amd64";
      sha256 = "8a4897031de9a5a566a6a0bc6eff2185d98bb47f1e179643a3fbe7523723ce58";
    };
  };
  system = stdenvNoCC.hostPlatform.system;
  asset = assets.${system} or (throw "grip-live-diff: no release asset for ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "grip-live-diff";
  inherit version;

  src = fetchurl {
    url = "https://github.com/babs/grip-live-diff/releases/download/v${version}/grip-live-diff-${asset.name}.xz";
    inherit (asset) sha256;
  };

  nativeBuildInputs = [ xz ];
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  # Upstream builds with CGO_ENABLED=0. Preserve the standalone release binary.
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    xz -dc "$src" > "$out/bin/grip-live-diff"
    chmod 755 "$out/bin/grip-live-diff"
    runHook postInstall
  '';

  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/grip-live-diff" --version | grep -F 'v${version}'
    runHook postInstallCheck
  '';

  meta = {
    description = "GitHub-style Markdown previews with live diffs and annotations";
    homepage = "https://github.com/babs/grip-live-diff";
    license = lib.licenses.mit;
    platforms = builtins.attrNames assets;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "grip-live-diff";
  };
}
