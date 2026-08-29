# moshi-hook — the companion daemon that reports local agent events (prompt
# start, tool activity, permission requests, turn complete) to the Moshi phone
# app, and carries approval round-trips back.
#
# Lives in the PORTABLE layer on purpose: the machine that wants this is the
# twincounsel loop VM, which consumes hm-core.nix as an opaque module. Default
# OFF, like kenji.desktop.enable — flip it in mkLoopVM's base fragment:
#   kenji.moshi.enable = true;
#
# Two things stay imperative and cannot move into Nix:
#
#   moshi-hook pair --token <token>   # writes a secret; never goes in git
#   moshi-hook install --target ...   # rewrites ~/.claude/settings.json et al,
#                                     # files no module here manages
#
# Do NOT also run `moshi-hook service install`. It writes its own
# systemd --user unit at the same name as the one declared below, and the two
# would fight over which ExecStart wins after a home-manager switch.
{ config, lib, pkgs, ... }:

let
  cfg = config.kenji.moshi;

  version = "0.3.11";

  # Hashes are upstream's published checksums.txt for this tag, converted to
  # SRI. Bumping the version means re-fetching that file — `moshi-hook update`
  # self-updates in place and cannot work against a read-only store, so the
  # version here is the only thing that moves this forward.
  assets = {
    x86_64-linux = {
      name = "moshi-hook_Linux_x86_64.tar.gz";
      hash = "sha256-dK80rw4U2Nf5+R6CYSNT5Q9RdFw5vQBxzxi/9PI5F6U=";
    };
    aarch64-linux = {
      name = "moshi-hook_Linux_arm64.tar.gz";
      hash = "sha256-udBB1P0fuAQ0P/r5ivMLDoYtXtgPHXfTEUbl1uhqY0k=";
    };
    x86_64-darwin = {
      name = "moshi-hook_Darwin_x86_64.tar.gz";
      hash = "sha256-XS7ZGh0NATyf8HKTMobZ2IR0J5bv11f8QpxUDXvrFsg=";
    };
    aarch64-darwin = {
      name = "moshi-hook_Darwin_arm64.tar.gz";
      hash = "sha256-rigkdzc5vHvV4Q9kSPZjUOheveAIfV/t23RBuk2EPvY=";
    };
  };

  inherit (pkgs.stdenv.hostPlatform) system;

  asset = assets.${system} or (throw "moshi-hook: upstream ships no asset for ${system}");

  moshi-hook = pkgs.stdenvNoCC.mkDerivation {
    pname = "moshi-hook";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://cdn.getmoshi.app/hook/v${version}/${asset.name}";
      inherit (asset) hash;
    };

    # The tarball unpacks flat (moshi-hook + README.md + docs/), no top-level
    # directory for stdenv to cd into.
    sourceRoot = ".";

    dontConfigure = true;
    dontBuild = true;

    # A fully static Go binary on every platform upstream ships — verified: the
    # ELF has no dynamic section at all. That is why this needs no
    # autoPatchelfHook here and no programs.nix-ld on the host, and why the same
    # derivation works on the non-NixOS loop VM.
    dontPatchELF = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 moshi-hook $out/bin/moshi-hook
      # Upstream's installer makes the same alias; `moshi .` opens/attaches a
      # session for a directory, which is the everyday entry point.
      ln -s moshi-hook $out/bin/moshi
      runHook postInstall
    '';

    meta = {
      description = "Companion daemon bridging local coding agents to the Moshi app";
      homepage = "https://getmoshi.app/docs/hooks";
      platforms = lib.attrNames assets;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      mainProgram = "moshi-hook";
    };
  };
in
{
  options.kenji.moshi.enable =
    lib.mkEnableOption "the moshi-hook agent-event daemon";

  config = lib.mkIf cfg.enable (lib.mkMerge [
    { home.packages = [ moshi-hook ]; }

    (lib.mkIf pkgs.stdenv.isLinux {
      systemd.user.services.moshi-hook = {
        Unit = {
          Description = "moshi-hook agent event daemon";
          Documentation = "https://getmoshi.app/docs/hooks";
        };

        Service = {
          ExecStart = "${lib.getExe moshi-hook} serve";

          # The daemon shells out to the tools it reports on: git for the diff
          # viewer, herdr/tmux for terminal context, ssh for Easy Pair. A
          # systemd --user unit inherits almost nothing, so name the profile
          # explicitly rather than relying on the login shell's PATH.
          Environment = [
            "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/usr/bin:/bin"
          ];

          Restart = "on-failure";
          RestartSec = 10;
        };

        Install.WantedBy = [ "default.target" ];
      };
    })
  ]);
}
