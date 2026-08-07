{
  description = "NixOS systems and tools by mitchellh";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    # Used to get ibus 1.5.29 which has some quirks we want to test.
    nixpkgs-old-ibus.url = "github:nixos/nixpkgs/e2dd4e18cc1c7314e24154331bae07df76eb582f";

    # We use the unstable nixpkgs repo for some packages.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Build a custom WSL installer
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    # snapd
    nix-snapd.url = "github:nix-community/nix-snapd";
    nix-snapd.inputs.nixpkgs.follows = "nixpkgs";

    # https://github.com/cpick/nix-rosetta-builder
    nix-rosetta-builder.url = "github:cpick/nix-rosetta-builder";
    nix-rosetta-builder.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      # We need to use nightly home-manager because it contains this
      # fix we need for nushell nightly:
      # https://github.com/nix-community/home-manager/commit/a69ebd97025969679de9f930958accbe39b4c705
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # I think technically you're not supposed to override the nixpkgs
    # used by neovim but recently I had failures if I didn't pin to my
    # own. We can always try to remove that anytime.
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
    };

    # Other packages
    jujutsu.url = "github:martinvonz/jj";
    zig.url = "github:mitchellh/zig-overlay";

    # herdr terminal multiplexer (not in nixpkgs) — consumed by kenjihash's
    # home-manager layer via inputs.herdr.packages.<system>.default.
    herdr.url = "github:ogulcancelik/herdr";

    # Non-flakes
    theme-bobthefish.url = "github:oh-my-fish/theme-bobthefish/e3b4d4eafc23516e35f162686f08a42edf844e40";
    theme-bobthefish.flake = false;
    fish-fzf.url = "github:jethrokuan/fzf/24f4739fc1dffafcc0da3ccfbbd14d9c7d31827a";
    fish-fzf.flake = false;
    fish-foreign-env.url = "github:oh-my-fish/plugin-foreign-env/dddd9213272a0ab848d474d0cbde12ad034e65bc";
    fish-foreign-env.flake = false;
  };

  outputs = { nixpkgs, ... }@inputs: let
    # Overlays is the list of overlays we want to apply from flake inputs.
    overlays = [
      inputs.jujutsu.overlays.default
      inputs.zig.overlays.default

      (_final: prev: let
        system = prev.stdenv.hostPlatform.system;
        unstable = import inputs.nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      in {
        # gh CLI on stable has bugs.
        gh = unstable.gh;

        # Want the latest version of these
        nushell = unstable.nushell;

        # Agent CLIs. These ship multiple times a week and nixos-26.05 froze in
        # late May — stable is ~74 patch releases behind on claude-code, and
        # grok-build (the real xAI CLI) is not in stable at all. Consumed by
        # modules/agent-clis.nix. Same six that twincounsel/nix's
        # overlays.agentClis pins; keep the two lists in step.
        inherit (unstable)
          claude-code
          codex
          gemini-cli
          opencode
          pi-coding-agent
          grok-build
          ;

        ibus = prev.ibus;
        ibus_stable = prev.ibus;
        ibus_1_5_29 = inputs.nixpkgs-old-ibus.legacyPackages.${system}.ibus;
        ibus_1_5_31 = unstable.ibus;
      })
    ];

    mkSystem = import ./lib/mksystem.nix {
      inherit overlays nixpkgs inputs;
    };

    # The PORTABLE half of my home-manager layer, exported for foreign flakes:
    #   mkLoopVM { personalModule = inputs.kenji-nix-config.homeManagerModules.default; }
    # `inputs` is closed over HERE, because the module needs inputs.herdr. That
    # is the whole trick: a consuming flake never has to pass specialArgs or
    # know anything about my inputs — it can treat this as an opaque module.
    personalModule = import ./users/kenjihash/hm-core.nix {
      inherit inputs;
      isWSL = false;
    };

    # pkgs for STANDALONE home-manager. Must mirror what mkSystem gives the
    # NixOS module: the layer contains unfree packages (_1password-cli) and
    # overlay-pinned ones. The module cannot set nixpkgs.* itself (see the
    # hm-core.nix header), so it has to happen out here.
    hmPkgs = system: import nixpkgs {
      inherit system overlays;
      config.allowUnfree = true;
    };

    mkHome = { system, username, homeDirectory ? "/home/${username}", modules ? [ ] }:
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = hmPkgs system;
        modules = [
          personalModule
          { home.username = username; home.homeDirectory = homeDirectory; }
        ] ++ modules;
      };
  in {
    homeManagerModules.default = personalModule;

    # Arch parity with the cloud loop VM (x86_64), plus this box's arch. Build
    # gates only — `nix flake check` cannot see these outputs, so the Makefile's
    # explicit `nix eval` lines are the real coverage.
    homeConfigurations = {
      "kenji@x86_64-linux" = mkHome { system = "x86_64-linux"; username = "kenji"; };
      "kenji@aarch64-linux" = mkHome { system = "aarch64-linux"; username = "kenji"; };
    };

    nixosConfigurations.vm-aarch64 = mkSystem "vm-aarch64" {
      system = "aarch64-linux";
      user   = "mitchellh";
    };

    nixosConfigurations.vm-aarch64-utm = mkSystem "vm-aarch64-utm" {
      system = "aarch64-linux";
      user   = "mitchellh";
    };

    nixosConfigurations.dev = mkSystem "dev" {
      system = "aarch64-linux";
      user   = "kenjihash";
    };

    nixosConfigurations.wsl = mkSystem "wsl" {
      system = "x86_64-linux";
      user   = "mitchellh";
      wsl    = true;
    };

    darwinConfigurations.macbook-pro-m1 = mkSystem "macbook-pro-m1" {
      system = "aarch64-darwin";
      user   = "mitchellh";
      darwin = true;
    };
  };
}
