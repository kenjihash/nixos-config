{ pkgs, inputs, ... }:

{
  # https://github.com/nix-community/home-manager/pull/2408
  environment.pathsToLink = [ "/share/fish" ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  # Since we're using fish as our shell
  programs.fish.enable = true;

  # Required because LazyVim installs unpatched (non-Nix) binaries via Mason;
  # nix-ld lets those dynamically-linked binaries run on NixOS. (Matches
  # mitchellh/nixos-config's users/mitchellh/nixos.nix.)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add any missing dynamic libraries for unpackaged programs here.
  ];

  users.users.kenjihash = {
    isNormalUser = true;
    home = "/home/kenjihash";
    extraGroups = [ "docker" "wheel" ];
    shell = pkgs.fish;

    # Password for console + GUI (lightdm) login, from `mkpasswd -m sha-512`.
    # SSH still uses the key below; sudo stays passwordless (vm-shared sets
    # security.sudo.wheelNeedsPassword = false). Fine to commit for a local
    # throwaway VM; for cloud VMs switch to hashedPasswordFile / sops so no
    # hash lives in git.
    hashedPassword = "$6$iNFqj7Xh4a.tK9bI$VJlLfcHbUGjqYKdD.2/vL/BfMYghQ7ETVDWDNiueXaCw8HVbT65xWA.wMeOPWHyxdaoozKUkJEpTL4CRcQZRF0";

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILpBz7YtGM5kte+NX5qy0x7gy6TKA5yO7GJEkw5kSRaW kenji.hashimoto@gmail.com"
    ];
  };
}
