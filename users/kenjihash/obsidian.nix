# Obsidian Headless (`ob`) — Obsidian Sync/Publish without the desktop app —
# plus one systemd --user unit per vault running `ob sync --continuous`.
#
# Use this flake's pinned nixpkgs-unstable so foreign consumers of hm-core.nix
# receive the package even when their global pkgs lacks obsidian-headless.
# Importing a separate package set also works with home-manager.useGlobalPkgs.
# The package is unfree; installation follows its declared platform support.
#
# The sync units are opt-in per vault:
#   kenji.obsidian.vaults.notes = "${config.home.homeDirectory}/notes";
#
# Login and vault linking stay imperative — they write the account token and
# the E2E encryption password, which never go in git. Once per machine:
#
#   ob login
#   ob sync-setup --vault <remote name or id> --path <same path as above>
#
# then `systemctl --user restart obsidian-sync-<name>`. Until that is done the
# unit fails and retries every RestartSec, which is harmless and loud in
# `journalctl --user -u obsidian-sync-<name>`.
{ inputs }:

{ config, lib, pkgs, ... }:

let
  cfg = config.kenji.obsidian;
  obsidianPkgs = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  package = obsidianPkgs.obsidian-headless;

  available = lib.meta.availableOn pkgs.stdenv.hostPlatform package;
in
{
  options.kenji.obsidian.vaults = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = lib.literalExpression ''{ notes = "''${config.home.homeDirectory}/notes"; }'';
    description = ''
      Local vault paths to keep continuously synced with Obsidian Sync, keyed by
      the name used in the unit (obsidian-sync-<name>). Each path must already
      be linked with `ob sync-setup`.
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf available { home.packages = [ package ]; })

    (lib.mkIf (cfg.vaults != { }) {
      assertions = [
        {
          assertion = available;
          message = "kenji.obsidian.vaults is set, but this flake's pinned obsidian-headless package does not support this platform.";
        }
      ];

      systemd.user.services = lib.mapAttrs' (name: path:
        lib.nameValuePair "obsidian-sync-${name}" {
          Unit = {
            Description = "Obsidian Sync (headless) for ${path}";
            Documentation = "https://obsidian.md/help/headless";
          };

          Service = {
            ExecStart = "${lib.getExe package} sync --continuous --path ${lib.escapeShellArg path}";
            # ob traps SIGTERM and shuts the sync loop down itself. No
            # network-online.target ordering: the --user manager cannot see the
            # system one, so a start while offline just fails and retries.
            Restart = "on-failure";
            RestartSec = 30;
          };

          Install.WantedBy = [ "default.target" ];
        }) cfg.vaults;
    })
  ];
}
