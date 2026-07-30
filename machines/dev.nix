{ lib, pkgs, ... }: {
  # Reuse Mitchell's VMware-Fusion-on-Apple-Silicon machine verbatim
  # (open-vm-tools, ens160 DHCP, x86 binfmt, /host mount, vm-shared base +
  # i3/plasma/gnome specializations). vm-shared already sets
  # networking.hostName = "dev", so no override is needed here.
  imports = [ ./vm-aarch64.nix ];

  # vm-shared.nix sets substituters/trusted-public-keys to ONLY Mitchell's
  # cachix, which (being normal definitions) replaces and drops the
  # cache.nixos.org defaults. Re-add the upstream cache so we get binary-cache
  # hits instead of building from source. listOf options merge across modules,
  # so these concatenate with vm-shared's — we keep both caches.
  nix.settings.substituters = [ "https://cache.nixos.org/" ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];

  # VMware's NAT DNS (192.168.204.2) stalls as the first resolver, which
  # breaks name resolution on this VM. Pin public resolvers so DNS just works
  # without hand-editing /etc/resolv.conf on every rebuild.
  networking.nameservers = [ "8.8.8.8" "1.1.1.1" ];

  # NetworkManager at the base so networking works in EVERY boot entry —
  # including the i3 specialization, which doesn't run GNOME (GNOME is what
  # pulled in NetworkManager for the default boot). NM manages the NIC by
  # device, so it doesn't matter that this VM enumerates ethernet as enp2s0
  # rather than Mitchell's hardcoded ens160.
  networking.networkmanager.enable = true;

  # NM otherwise appends VMware's NAT resolver (192.168.204.2) ahead of the
  # pinned nameservers, and DNS hangs on it. Tell NM not to manage resolv.conf;
  # resolvconf then writes ONLY networking.nameservers below.
  networking.networkmanager.dns = "none";

  # Render at the display's native (retina) resolution via `xrandr --auto` in
  # the i3 config; dpi 192 scales the UI to a readable size (2x) so text stays
  # crisp instead of VMware upscaling a lower-res framebuffer.
  specialisation.i3.configuration.services.xserver.dpi = lib.mkForce 192;

  # InconsolataGo Nerd Font (from the Brewfile). System-level so fontconfig
  # discovers it for ghostty/i3.
  fonts.packages = [ pkgs.nerd-fonts.inconsolata-go ];

  # This is a desktop machine — turn on kenjihash's GUI home-manager layer
  # (ghostty/rofi/i3). Headless machines (e.g. a twincounsel EC2 loop VM) leave
  # this off and get only the core ergonomics (shell/editor/herdr/CLIs/git).
  home-manager.users.kenjihash.kenji.desktop.enable = true;
}
