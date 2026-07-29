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

    # Password login is disabled for now (SSH-key login only, sudo is
    # passwordless via vm-shared's security.sudo.wheelNeedsPassword = false).
    # To enable console/password login later, on the VM run:
    #   mkpasswd -m sha-512
    # and set:  hashedPassword = "<the hash>";  then re-switch.

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMNrAHuHZIwRNjJ2U5HHdx6GEYIPivhpOQ4GNtOonIzO kenji@twincounsel.com"
    ];
  };
}
