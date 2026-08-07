# Standalone agent-CLI layer.
#
# Deliberately duplicates the catalog in twincounsel/nix/modules/devtools.nix so
# that THIS repo stands alone: a fresh box, the Mac, or a personal VM gets the
# agent CLIs without a private-repo flake input, SSH auth to a work remote, or
# any knowledge of twincounsel at all.
#
# The duplication is intentional and cheap (six attribute names). Sharing it
# would mean either pointing twincounsel at this repo — inverting the dependency
# so a product repo imports a personal one — or pointing this repo at
# twincounsel, which is exactly the coupling this file exists to avoid. Keep the
# two catalogs in step by hand.
#
# On `dev`, twincounsel's devtools module is the provider and this stays off;
# see machines/dev.nix. The assertion below explains why both at once is a bad
# idea even though it is not a build error.
#
# Requires the agent-CLI pins in flake.nix's overlay and allowUnfree, both of
# which lib/mksystem.nix already arranges.
{ config, lib, pkgs, ... }:

let
  cfg = config.kenji.agents;

  # Keyed by the name I actually say. Three of the six differ from their
  # nixpkgs attribute, and guessing wrong silently installs a different program:
  #   grok -> grok-build       (`grok-cli` is superagent-ai's third-party
  #                             wrapper, NOT xAI's CLI)
  #   pi   -> pi-coding-agent  (`pi` is not a top-level attr)
  # `codex-cli` and `google-gemini-cli` do not exist.
  catalog = {
    claude-code = pkgs.claude-code;
    codex = pkgs.codex;
    gemini-cli = pkgs.gemini-cli;
    opencode = pkgs.opencode;
    pi = pkgs.pi-coding-agent;
    grok = pkgs.grok-build;
  };

  # Keeps this evaluable on aarch64-darwin, where not all six are available.
  # The enum stays complete so an explicit request for a missing tool still
  # errors loudly instead of being silently dropped.
  available = lib.filterAttrs (_: p: lib.meta.availableOn pkgs.stdenv.hostPlatform p) catalog;
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
          the two flakes pin DIFFERENT nixpkgs-unstable revisions, and whichever
          overlay is applied last silently decides which claude-code you get.
          Nothing in either configuration makes that visible.
        '';
      }
    ];
  };
}
