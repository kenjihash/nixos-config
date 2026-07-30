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
    hashedPassword = "$6$7NDULjR4jCxGkwie$BA9LYq6w9D4W6b4AL8ld/XdNSNvaC8nQfm8xwIyFbO6upqFxYeN1SN7xqoB9OFA16g2mfD614f8f4XgGxDnbO0";

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJjiRR+xiWj2RHhd80vcd8bcFeZHV00REGGa9Ps0zoyX kenji.hashimoto@gmail.com"
    ];
  };
}
