# Machine-specific wrapper around the portable core.
#
# hm-core.nix is what flake.nix exports as homeManagerModules.default for
# foreign flakes (twincounsel's mkLoopVM). Everything in THIS file is a fact
# about my own machines and must not leak into that export: the personal git
# identity, the SSH signing key, and the assumption that this repo is checked
# out at ~/nixos-config.
#
# The signature is unchanged so lib/mksystem.nix keeps working verbatim.
{ isWSL ? false, inputs, ... }:

{ config, lib, pkgs, ... }:

{
  imports = [ (import ./hm-core.nix { inherit inputs isWSL; }) ];

  # I edit nvim lua on these boxes, so ~/.config/nvim must be writable and
  # lazy.nvim must be able to update lazy-lock.json. A loop VM gets "store".
  kenji.nvim.mode = "outOfStore";

  # SSH commit signing with the key copied from the Mac. A loop VM gets null
  # (no key on the box; push is gh device flow).
  kenji.git.signingKey = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";

  # Personal identity. On a twincounsel loop VM, mkLoopVM's base fragment owns
  # these as kenji@twincounsel.com with a PLAIN definition — which is exactly
  # why they are here and not in hm-core.nix.
  programs.git.settings = {
    user.name = "Kenji Hashimoto";
    user.email = "kenji.hashimoto@gmail.com";
  };
}
