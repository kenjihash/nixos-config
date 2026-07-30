# Kenji's i3 desktop layer (ghostty, rofi, i3 + i3status config), split out of
# the core home-manager module so headless machines — e.g. a twincounsel EC2
# loop VM — reuse the core ergonomics (shell, editor, herdr, CLIs, git) WITHOUT
# pulling in a GUI. Enable per-machine with:
#   home-manager.users.kenjihash.kenji.desktop.enable = true;
{ config, lib, pkgs, ... }:

{
  options.kenji.desktop.enable =
    lib.mkEnableOption "the i3 desktop layer (ghostty, rofi, i3/i3status config)";

  config = lib.mkIf config.kenji.desktop.enable {
    home.packages = [
      pkgs.rofi
      pkgs.ghostty # terminal ($mod+n)
    ];

    # i3's window colors come from the inline fallbacks in ./i3.
    xdg.configFile."i3/config".text = builtins.readFile ./i3;
    xdg.configFile."rofi/config.rasi".text = builtins.readFile ./rofi;
    xdg.configFile."ghostty/config".source = ./ghostty;

    programs.i3status = {
      enable = true;
      general = {
        colors = true;
        color_good = "#8C9440";
        color_bad = "#A54242";
        color_degraded = "#DE935F";
      };
      modules = {
        ipv6.enable = false;
        "wireless _first_".enable = false;
        "battery all".enable = false;
      };
    };
  };
}
