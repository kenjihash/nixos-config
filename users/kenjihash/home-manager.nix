{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  shellAliases = {
    l = "less -SN";
    v = "nvim";
    g = "rg --line-number";
    gs = "git status";
    c = "clear";
    ll = "ls -l";
    la = "ls -la";
  };
in {
  # We mix nixpkgs 26.05 with home-manager master, so silence the version
  # check and pin a conservative state version.
  home.enableNixpkgsReleaseCheck = false;
  home.stateVersion = "24.11";

  xdg.enable = true;

  #---------------------------------------------------------------------
  # Packages — keep the personal layer small and global-ergonomic.
  # Project/cloud toolchains (aws, terraform, kubectl, docker, pnpm, ...)
  # come from the team base or per-project direnv, NOT here.
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

    # Agent CLIs (claude-code is pinned to unstable via the flake overlay)
    claude-code
    codex

    # Thin runtime base for editor/agent tooling; project versions via direnv
    nodejs
    python3
    uv

    # Editor — LazyVim config is vendored + symlinked below. NOTE: mason is
    # disabled in the vendored config, so tools come from Nix, not auto-install.
    neovim
    gcc          # C compiler for nvim-treesitter (main) to build parsers
    tree-sitter  # tree-sitter CLI, also required by nvim-treesitter (main)
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
  };

  programs.starship.enable = true;
  programs.zoxide.enable = true;
  programs.fzf.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Neovim (LazyVim) config, vendored in this repo. We symlink ~/.config/nvim
  # to the repo checkout in $HOME via mkOutOfStoreSymlink (NOT into /nix/store),
  # so the dir is WRITABLE: lazy.nvim can update lazy-lock.json, and you can
  # edit nvim lua live without a rebuild. Requires the repo at ~/nixos-config.
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nixos-config/users/kenjihash/nvim";

  #---------------------------------------------------------------------
  # Git — identity + SSH commit signing with the key copied from the Mac
  #---------------------------------------------------------------------
  programs.git = {
    enable = true;
    lfs.enable = true; # gitconfig defines LFS filters

    settings = {
      user.name = "Kenji Hashimoto";
      user.email = "kenji@twincounsel.com";
      user.signingKey = "/home/kenjihash/.ssh/id_ed25519.pub";
      github.user = "kenjihash";

      gpg.format = "ssh";
      commit.gpgSign = true;
      tag.gpgSign = true;

      init.defaultBranch = "main";
      push.default = "tracking";
      color.ui = true;
    };
  };
}
