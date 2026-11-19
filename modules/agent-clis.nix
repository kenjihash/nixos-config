# Install the personal agent CLI catalog without importing the private team
# flake. The team consumes this repository's Home Manager module, so importing
# it back here would create a dependency cycle. Keep the catalogs in step.
#
# This module supplies agent tools on dev. The exported Home Manager module
# leaves system-wide agent selection to the consuming host.
# Requires flake.nix's CLI overlay and allowUnfree from lib/mksystem.nix.
{ config, lib, pkgs, ... }:

let
  cfg = config.kenji.agents;

  # Keyed by the command name. Some entries differ from their
  # nixpkgs attribute, and guessing wrong silently installs a different program:
  #   grok -> grok-build       (`grok-cli` is superagent-ai's third-party
  #                             wrapper, NOT xAI's CLI)
  #   pi   -> pi-coding-agent  (`pi` is not a top-level attr)
  #   agy  -> antigravity-cli  (`antigravity` is the IDE — mainProgram
  #                             antigravity-ide — not the terminal client. The
  #                             CLI's binary really is `agy`.)
  #   amp  -> amp-cli          (`amp` is a text editor)
  #   t3   -> t3code           (`t3` formats output streams)
  # `codex-cli` does not exist.
  #
  # `agy` replaced the former `gemini-cli` entry: Google retired Gemini CLI for
  # unpaid-tier and AI Pro/Ultra accounts, and nixpkgs marks gemini-cli with a
  # `removal` problem. See the overlay in flake.nix.
  catalog = {
    claude-code = pkgs.claude-code;
    codex = pkgs.codex;
    agy = pkgs.antigravity-cli;
    opencode = pkgs.opencode;
    pi = pkgs.pi-coding-agent;
    grok = pkgs.grok-build;
    amp = pkgs.amp-cli;
    droid = pkgs.droid;
    kiro-cli = pkgs.kiro-cli;
    t3 = pkgs.t3code;
  };

  # Keeps this evaluable on aarch64-darwin, where some tools are unavailable.
  # The enum stays complete so an explicit request for a missing tool still
  # errors loudly instead of being silently dropped.
  available = lib.filterAttrs (_: p: lib.meta.availableOn pkgs.stdenv.hostPlatform p) catalog;

  syncCodexDaemon = pkgs.writeShellScript "sync-codex-daemon" ''
    set -eu
    codexHome="''${CODEX_HOME:-$HOME/.codex}"
    daemon="$codexHome/packages/app-server-daemon"
    legacy="$codexHome/packages/standalone"
    state="$codexHome/app-server-daemon"

    # A legacy standalone CLI selection can exist before daemon use.
    if [[ ! -e "$daemon/current" && ! -L "$daemon/current" ]]; then
      if [[ ! -e "$legacy/current" && ! -L "$legacy/current" ]] ||
         [[ ! -f "$state/app-server.pid" && ! -f "$state/app-server.stderr.log" &&
            ! -f "$state/app-server-updater.pid" && ! -f "$state/app-server-updater.stderr.log" ]]; then
        exit 0
      fi
    fi

    daemon_is_current() {
      local item
      [[ ! -e "$daemon/auto-update-version" && ! -L "$daemon/auto-update-version" ]] || return 1
      for item in codex-package.json bin codex-path codex-resources; do
        ${pkgs.diffutils}/bin/diff -qr "${pkgs.codex}/libexec/codex/$item" \
          "$daemon/current/$item" >/dev/null 2>&1 || return 1
      done
    }
    if daemon_is_current; then
      exit 0
    fi

    userName="$(${pkgs.coreutils}/bin/id -un)"
    export PATH="/run/wrappers/bin:$HOME/.nix-profile/bin:/etc/profiles/per-user/$userName/bin:/run/current-system/sw/bin"
    # A daemon restarted by Codex must outlive the activation service.
    exec ${pkgs.systemd}/bin/systemd-run --user --scope --quiet -- \
      ${pkgs.codex}/bin/codex app-server daemon update --from-cli --yes
  '';
in
{
  options.kenji.agents = {
    enable = lib.mkEnableOption "agent CLIs from my own config (no twincounsel dependency)";

    tools = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames catalog));
      default = lib.attrNames available;
      defaultText = lib.literalExpression "all tools available on this platform";
      description = "Which agent CLIs to install system-wide.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = map (n: catalog.${n}) cfg.tools;

    system.userActivationScripts.codex-daemon = lib.mkIf (builtins.elem "codex" cfg.tools) {
      text = "${syncCodexDaemon}";
    };

    assertions = [
      {
        # attrByPath rather than a direct read: twincounsel's module may not be
        # imported on this machine at all, and reading an undefined option
        # throws rather than returning null.
        assertion = !(lib.attrByPath [ "twincounsel" "devtools" "agents" "enable" ] false config);
        message = ''
          Both kenji.agents.enable and twincounsel.devtools.agents.enable are on.
          Pick one provider.

          This is not a build collision — both modules read the same `pkgs`, so
          environment.systemPackages just deduplicates. The problem is subtler:
          the two flakes pin their agent CLIs independently — different
          nixpkgs-unstable revisions for the channel lane, and their own
          upstream/*.json release data for the fast lane — so whichever overlay
          is applied last silently decides which claude-code you get. Nothing
          in either configuration makes that visible.
        '';
      }
    ];
  };
}
