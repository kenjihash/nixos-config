{ lib, stdenv, opencode, fetchFromGitHub }:

let
  version = "2.3.2";
in
# The verified Bun dependency hash is for Linux. Darwin uses its channel build.
if stdenv.hostPlatform.isLinux && lib.versionOlder opencode.version version then
  opencode.overrideAttrs (final: old: {
    inherit version;
    src = fetchFromGitHub {
      owner = "anomalyco";
      repo = "opencode";
      tag = "v${final.version}";
      hash = "sha256-yEdLD000KJPNkuowiy4g+sHV+7dm3xazKTEf15ZIYKs=";
    };
    node_modules = old.node_modules.overrideAttrs {
      outputHash = "sha256-1mWmG+sGm7U8mkC8mF5DWq8kUrJYV6o+nFTdPJpPOsc=";
    };
  })
else
  opencode
