# The PORTABLE core of Kenji's personal home-manager layer.
#
# flake.nix exports this as `homeManagerModules.default`, so it is consumed by
# FOREIGN flakes — the twincounsel team flake's mkLoopVM, per
# docs/development/cloud-dev-vms.md rung 3. That has consequences, all
# load-bearing:
#
#   * It must NOT set `home.username` / `home.homeDirectory`. Home-manager's
#     NixOS module sets those plainly (nixos/common.nix), and a second
#     definition is a conflict error.
#   * It must NOT set `nixpkgs.config` / `nixpkgs.overlays`. Under
#     `home-manager.useGlobalPkgs = true` those are asserted away
#     (modules/misc/nixpkgs-disabled.nix). The CONSUMER's pkgs must therefore
#     supply `allowUnfree` — claude-code and _1password-cli are unfree — and,
#     ideally, the unstable pins for the agent CLIs.
#   * It must NOT set a git identity, a home path, or a repo checkout path.
#     The base fragment in mkLoopVM owns `user.name`/`user.email` with a PLAIN
#     definition; anything host-specific here is an option below, defaulted to
#     whatever is safe on a machine we know nothing about.
#
# Machine-specific facts live in ./home-manager.nix, which wraps this.
{ isWSL ? false, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  cfg = config.kenji;

  # false under the NixOS/nix-darwin module, true under
  # home-manager.lib.homeManagerConfiguration. `submoduleSupport.enable` is
  # marked internal in home-manager, but it is the only reliable signal and is
  # stable in practice.
  isStandalone = !config.submoduleSupport.enable;

  shellAliases = {
    # eza (icons render — InconsolataGo Nerd Font is installed)
    ls = "eza --group-directories-first --icons=auto";
    ll = "eza -l  --group-directories-first --icons=auto --git"; # long + git status
    la = "eza -la --group-directories-first --icons=auto --git"; # long + hidden
    lt = "eza --tree --level=2 --icons=auto"; # 2-level tree

    l = "less -SN";
    v = "nvim";
    g = "rg --line-number";
    gs = "git status";
    c = "clear";
  };

  #-------------------------------------------------------------------------
  # Agent-CLI editor mode. Both tools ship `normal` bindings by default and
  # both take a config key:
  #   codex        ~/.codex/config.toml      [tui] vim_mode_default = true
  #   claude-code  ~/.claude/settings.json   "editorMode": "vim"
  #
  # These are SEEDED, not managed, and that is deliberate. Both files are
  # rewritten by the tool itself — codex persists `[projects.*] trust_level`
  # and TUI nux counters, Claude Code persists every /config change — so the
  # herdr pattern (xdg.configFile -> /nix/store) is the wrong shape here.
  # Verified against codex 0.145.0: it resolves the symlink and writes its
  # tempfile NEXT TO the resolved target, so the first `trust this repo`
  # aborts with
  #     failed to persist config at /nix/store/...-config.toml
  #     Read-only file system (os error 30) at path "/nix/store/.tmpXXXXXX"
  # It does not clobber the symlink, it just cannot save anything, ever.
  #
  # So: write the key once if it is absent, then never touch it again. An
  # explicit `false`/`"normal"` set by hand survives — the guard is on the key
  # existing, not on its value.
  #-------------------------------------------------------------------------
  codexVimMode = pkgs.writeShellScript "codex-seed-vim-mode" ''
    set -eu
    cfg="$HOME/.codex/config.toml"
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$cfg")"
    [ -e "$cfg" ] || : > "$cfg"

    # Any occurrence at all — mine or one I later flipped to false.
    if ${pkgs.gnugrep}/bin/grep -q '^[[:space:]]*vim_mode_default[[:space:]]*=' "$cfg"; then
      exit 0
    fi

    # A bare `[tui]` table may already exist (distinct from `[tui.foo]`, which
    # codex writes on its own). Appending a second one is a TOML parse error,
    # so insert into the first instead.
    if ${pkgs.gnugrep}/bin/grep -q '^\[tui\][[:space:]]*$' "$cfg"; then
      ${pkgs.gnused}/bin/sed -i '0,/^\[tui\][[:space:]]*$/s//[tui]\nvim_mode_default = true/' "$cfg"
    else
      printf '\n[tui]\nvim_mode_default = true\n' >> "$cfg"
    fi
  '';

  claudeVimMode = pkgs.writeShellScript "claude-seed-vim-mode" ''
    set -eu
    cfg="$HOME/.claude/settings.json"
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$cfg")"
    [ -s "$cfg" ] || echo '{}' > "$cfg"

    tmp="$(${pkgs.coreutils}/bin/mktemp "$cfg.XXXXXX")"
    ${pkgs.jq}/bin/jq 'if has("editorMode") then . else .editorMode = "vim" end' \
      "$cfg" > "$tmp"
    ${pkgs.coreutils}/bin/mv "$tmp" "$cfg"
  '';
in
{
  # The i3 desktop layer (ghostty/rofi/i3) lives in gui.nix, gated by
  # kenji.desktop.enable — off by default so headless machines get core only.
  # moshi.nix is the same shape: the moshi-hook daemon, gated by
  # kenji.moshi.enable, off by default and turned on by the loop VM.
  imports = [ ./gui.nix ./moshi.nix ];

  options.kenji = {
    nvim.mode = lib.mkOption {
      type = lib.types.enum [ "store" "outOfStore" "none" ];
      default = "store";
      description = ''
        How ~/.config/nvim is materialised.
          "store"      – read-only symlink to the vendored config in /nix/store.
                         The ONLY mode that works when this repo is consumed as
                         a flake input, because no checkout exists in $HOME.
          "outOfStore" – mkOutOfStoreSymlink into `kenji.nvim.repoPath`, so the
                         directory is WRITABLE: lazy.nvim can update
                         lazy-lock.json and nvim lua is editable without a
                         rebuild. Requires the repo checked out there.
          "none"       – do not manage ~/.config/nvim at all.
      '';
    };

    nvim.repoPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/nixos-config";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/nixos-config"'';
      description = "Checkout of this repo. Only read when nvim.mode == \"outOfStore\".";
    };

    git.signingKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/kenjihash/.ssh/id_ed25519.pub";
      description = ''
        Public SSH key for commit/tag signing. When null (the default) signing
        is disabled ENTIRELY. That default is mandatory, not conservative: a
        loop VM has no key and uses `gh auth login` device flow for push, and
        setting commit.gpgSign = true with no key breaks every commit.
      '';
    };

    herdr.enable = lib.mkEnableOption "the herdr multiplexer (from its own flake input)" // {
      default = true;
    };

    agentClis.vimMode = lib.mkEnableOption "vi keybindings in the codex and claude prompt editors" // {
      default = true;
    };
  };

  config = lib.mkMerge [
    {
      # We mix nixpkgs 26.05 with home-manager master, so silence the check.
      home.enableNixpkgsReleaseCheck = false;

      # mkDefault so a consuming base fragment (mkLoopVM) can own it plainly on
      # a freshly built VM without a conflict.
      home.stateVersion = lib.mkDefault "24.11";

      xdg.enable = true;

      #---------------------------------------------------------------------
      # Packages — keep the personal layer small and global-ergonomic.
      # Project/cloud toolchains (aws, terraform, kubectl, docker, pnpm, ...)
      # come from the team base or per-project direnv, NOT here. Agent CLIs
      # likewise: they are the base's job now (modules/agent-clis.nix locally,
      # twincounsel's devtools module on a loop VM).
      #---------------------------------------------------------------------
      home.packages = with pkgs; [
        # Core ergonomics
        bat
        eza
        fd
        fzf
        ripgrep
        tree
        jq
        yq-go
        htop
        btop
        starship
        zoxide
        wget
        gh
        lazygit
        mosh
        _1password-cli

        # Agent-harness power tools (what Claude Code / Codex shell out to)
        ast-grep
        delta
        jc
        shellcheck
        shfmt

        # Thin runtime base for editor/agent tooling; project versions via direnv
        nodejs
        python3
        uv

        # Editor — LazyVim config is vendored + symlinked below. NOTE: mason is
        # disabled in the vendored config, so tools come from Nix, not auto-install.
        neovim
        gcc # C compiler for nvim-treesitter (main) to build parsers
        tree-sitter # tree-sitter CLI, also required by nvim-treesitter (main)

        # LSP servers + formatters for the LazyVim extras. mason is disabled, so
        # these come from Nix. (astro intentionally omitted for this VM.)
        lua-language-server # lua (LazyVim itself)
        stylua
        basedpyright # python
        ruff
        black
        typescript-language-server # typescript / js
        prettier
        marksman # markdown
        vscode-langservers-extracted # json / html / css / eslint
        yaml-language-server # yaml
      ];

      #---------------------------------------------------------------------
      # Env
      #---------------------------------------------------------------------
      home.sessionVariables = {
        LANG = "en_US.UTF-8";
        LC_ALL = "en_US.UTF-8";
        EDITOR = "nvim";
        PAGER = "less -FirSwX";
      };

      #---------------------------------------------------------------------
      # Shell = fish (native integrations, no runtime plugin manager)
      #---------------------------------------------------------------------
      programs.fish = {
        enable = true;
        shellAliases = shellAliases;
        interactiveShellInit = ''
          set -U fish_greeting ""
          fish_vi_key_bindings
        '';

        # PatrickF1/fzf.fish — the `History>` search with formatted timestamps
        # (matches the Mac), plus dir/variable/process widgets. Managed
        # declaratively (no fisher). Needs fzf/fd/bat, all in home.packages.
        plugins = [
          {
            name = "fzf-fish";
            src = pkgs.fishPlugins.fzf-fish.src;
          }
        ];
      };

      programs.starship.enable = true;
      programs.zoxide = {
        enable = true;
        options = [ "--cmd cd" ]; # cd = zoxide (frecency); `cd foo` jumps, `cdi` picks
      };
      programs.fzf = {
        enable = true;
        enableFishIntegration = false; # replaced by the fzf.fish plugin above (nicer history UI w/ real timestamps, not raw epoch)
      };

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      # herdr multiplexer config (vendored). Only config.toml is symlinked, so
      # herdr's runtime state (sessions, logs, sockets) stays writable in
      # ~/.config/herdr.
      xdg.configFile."herdr/config.toml".source = ./herdr/config.toml;

      #---------------------------------------------------------------------
      # Git — everything EXCEPT the identity, which the host owns. See the
      # header: base-owns-identity is the only unambiguous rule, because
      # programs.git.settings leaves are non-mergeable.
      #---------------------------------------------------------------------
      programs.git = {
        enable = true;
        lfs.enable = true; # gitconfig defines LFS filters

        # mkDefault on everything a team base fragment might also plausibly set.
        settings = {
          github.user = lib.mkDefault "kenjihash";
          init.defaultBranch = lib.mkDefault "main";
          push.default = lib.mkDefault "tracking";
          color.ui = lib.mkDefault true;
        };
      };
    }

    (lib.mkIf cfg.agentClis.vimMode {
      # entryAfter writeBoundary: these touch $HOME outside the generation, so
      # they must run once home-manager is done laying down its own links.
      # Unconditional (not gated on the CLIs being installed) — the config is
      # harmless when absent and the provider varies by machine: agent-clis.nix
      # locally, twincounsel's devtools module on a loop VM.
      home.activation.agentClisVimMode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${codexVimMode}
        run ${claudeVimMode}
      '';
    })

    (lib.mkIf cfg.herdr.enable {
      # Not in nixpkgs, so it comes from its own flake input.
      home.packages = [
        inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
    })

    (lib.mkIf (cfg.nvim.mode == "store") {
      xdg.configFile."nvim".source = ./nvim;
    })

    (lib.mkIf (cfg.nvim.mode == "outOfStore") {
      xdg.configFile."nvim".source =
        config.lib.file.mkOutOfStoreSymlink "${cfg.nvim.repoPath}/users/kenjihash/nvim";
    })

    (lib.mkIf (cfg.git.signingKey != null) {
      programs.git.settings = {
        user.signingKey = cfg.git.signingKey;
        gpg.format = "ssh";
        commit.gpgSign = true;
        tag.gpgSign = true;
      };
    })

    # The home-manager CLI, built from THIS flake's locked home-manager
    # (eval-config.nix sets programs.home-manager.path automatically). Only in
    # standalone mode — on `dev`, home-manager runs as a NixOS module and having
    # the CLI on PATH just invites two generations fighting over the same paths.
    (lib.mkIf isStandalone {
      programs.home-manager.enable = true;
    })
  ];
}
