# Obsidian Headless (`ob`) — Obsidian Sync/Publish without the desktop app —
# plus one systemd --user unit per vault running `ob sync --continuous`.
#
# The package is installed whenever pkgs carries it. It is only in
# nixpkgs-unstable, pinned by this flake's overlay; a foreign consumer of
# hm-core.nix whose pkgs lacks that pin just goes without, rather than failing
# to evaluate. Unfree, and Linux-only in nixpkgs.
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
{ config, lib, pkgs, ... }:

let
  cfg = config.kenji.obsidian;

  available = pkgs ? obsidian-headless
    && lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.obsidian-headless;
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
    (lib.mkIf available { home.packages = [ pkgs.obsidian-headless ]; })

    (lib.mkIf (cfg.vaults != { }) {
      assertions = [
        {
          assertion = available;
          message = "kenji.obsidian.vaults is set, but pkgs has no obsidian-headless for this platform (it comes from this flake's nixpkgs-unstable overlay, Linux only).";
        }
      ];

      systemd.user.services = lib.mapAttrs' (name: path:
        lib.nameValuePair "obsidian-sync-${name}" {
          Unit = {
            Description = "Obsidian Sync (headless) for ${path}";
            Documentation = "https://obsidian.md/help/headless";
          };

          Service = {
            ExecStart = "${lib.getExe pkgs.obsidian-headless} sync --continuous --path ${lib.escapeShellArg path}";
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
