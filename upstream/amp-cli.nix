{ amp-cli, fetchurl, lib, stdenvNoCC }:

let
  version = "0.0.1795104033-gfa5ada";
  download = platform: hash: fetchurl {
    url = "https://static.ampcode.com/cli/${version}/amp-${platform}.gz";
    inherit hash;
  };
  sources = {
    x86_64-linux = download "linux-x64-baseline" "sha256-BxWrRj2HY/2TmXAuf8K/JofXusL3xmsjxwVMFT94gBU=";
    aarch64-linux = download "linux-arm64" "sha256-kwG5PAZYIRNqF9VD0oLUXKHRFxuuo2oa581Ha1vaRGQ=";
    aarch64-darwin = download "darwin-arm64" "sha256-lrODM5JpaV6UpyAzxsZUa13m1sXnCEtBI8YKlUuVmj4=";
  };
in
if lib.versionOlder amp-cli.version version then
  amp-cli.overrideAttrs (old: {
    inherit version;
    src = sources.${stdenvNoCC.hostPlatform.system};
    passthru = old.passthru // { inherit sources; };
  })
else
  amp-cli
