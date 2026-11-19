{ lib, t3code, fetchFromGitHub }:

let
  version = "0.1.10";
in
if lib.versionOlder t3code.version version then
  t3code.unwrapped.overrideAttrs (final: old: {
    inherit version;
    src = fetchFromGitHub {
      owner = "pingdotgg";
      repo = "t3code";
      tag = "v${final.version}";
      hash = "sha256-zhScbDGW+bD2T7++YRUPY/y83SGE2080LxcGw3Txrso=";
    };
    pnpmDeps = old.pnpmDeps.overrideAttrs {
      outputHash = "sha256-27Ljt2lY4J1Fi3ddVIflPQ5erRqmgaZ8+YBH9fhCLzo=";
    };
  })
else
  t3code.unwrapped
