{ lib, pkgs, ... }: {
  # Reuse Mitchell's VMware-Fusion-on-Apple-Silicon machine (open-vm-tools,
  # DHCP, x86 binfmt, /host mount, vm-shared base). vm-shared already sets
  # networking.hostName = "dev", so no override is needed here. We DROP its
  # GNOME/plasma/gnome-ibus desktops in favor of i3-only (see the Desktop
  # section below) — done entirely in THIS file so upstream rebases stay clean.
  imports = [ ./vm-aarch64.nix ];

  # ── HOST REQUIREMENT: VMware Fusion network adapter MUST be "Bridged" ──
  # On macOS Sequoia 15.4+ (this Mac is macOS 26), Fusion's NAT DNS is broken:
  # the guest gets 192.168.x.2 as its resolver but that NAT DNS proxy stalls,
  # so name resolution fails in BOTH bootstrap stages (before any Nix config
  # applies) and at runtime. This is a documented Broadcom bug, and their
  # official workaround is to switch the VM's adapter from NAT to Bridged
  # (VM Settings → Network Adapter → Bridged). Bridged makes the guest get its
  # IP + DNS straight from the LAN router, bypassing Fusion's NAT entirely.
  #   https://techdocs.broadcom.com/us/en/vmware-cis/desktop-hypervisors/fusion-pro/13-0/release-notes/vmware-fusion-1363-release-notes.html
  # Consequence: the VM lives on the LAN subnet (10.0.0.x here), not the NAT
  # 192.168.204.x range — keep ~/.ssh/config's `Host dev` HostName in sync.

  # vm-shared.nix sets substituters/trusted-public-keys to ONLY Mitchell's
  # cachix, which (being normal definitions) replaces and drops the
  # cache.nixos.org defaults. Re-add the upstream cache so we get binary-cache
  # hits instead of building from source. listOf options merge across modules,
  # so these concatenate with vm-shared's — we keep both caches.
  nix.settings.substituters = [ "https://cache.nixos.org/" ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];

  # Belt-and-suspenders now that networking is Bridged (see HOST REQUIREMENT
  # above): Bridged already gives working DNS from the router, but pinning
  # public resolvers keeps runtime DNS deterministic and independent of
  # whatever the LAN hands out.
  networking.nameservers = [ "8.8.8.8" "1.1.1.1" ];

  # NetworkManager at the base so networking is always up regardless of desktop.
  # NM manages the NIC by device, so it doesn't matter that this VM enumerates
  # ethernet as enp2s0 rather than Mitchell's hardcoded ens160.
  networking.networkmanager.enable = true;

  # Tell NM not to manage resolv.conf so it doesn't prepend the router's
  # DHCP-supplied resolver ahead of the pinned nameservers; resolvconf then
  # writes ONLY networking.nameservers above.
  networking.networkmanager.dns = "none";

  #---------------------------------------------------------------------
  # Desktop: i3 ONLY (diverges from Mitchell's GNOME base + i3/plasma/
  # gnome-ibus specialisations). He keeps all of those to test Ghostty and
  # input methods across desktops; we just use the VM as a terminal, so we
  # drop them. All of this lives HERE, never in vm-shared.nix or
  # modules/specialization/*, so `git rebase main` onto upstream stays clean.
  #
  # `specialisation = lib.mkForce {}` does the heavy lifting: it discards the
  # i3/plasma/gnome-ibus specialisations from the imported modules AND — because
  # vm-shared gates the base GNOME/GDM on `config.specialisation != {}` — it
  # simultaneously disables those. That leaves NO desktop, so we define i3 as
  # the base ourselves below.
  specialisation = lib.mkForce {};

  services.xserver = {
    enable = true;
    xkb.layout = "us";

    # Native (retina) resolution via `xrandr --auto` in the i3 config; dpi 192
    # scales the UI 2x so text stays crisp instead of VMware upscaling a
    # lower-res framebuffer.
    dpi = 192;

    desktopManager = {
      xterm.enable = false;
      wallpaper.mode = "fill";
    };

    displayManager = {
      lightdm.enable = true;
      # Faster key repeat in the i3 session (matches Mitchell's i3 setup).
      sessionCommands = ''
        ${pkgs.xset}/bin/xset r rate 200 40
      '';
    };

    windowManager.i3.enable = true;
  };

  # Boot straight into i3 with no login prompt. lightdm + autoLogin is the
  # reliable NixOS path (a truly display-manager-less autologin is fragile on
  # VMware); the greeter is skipped, so a `make switch` that restarts the DM
  # just blinks back to i3 instead of hanging on GNOME's software-GL startup.
  services.displayManager = {
    defaultSession = "none+i3";
    autoLogin = {
      enable = true;
      user = "kenjihash";
    };
  };

  # Only one desktop now, so the boot menu drops the per-DE specialisation
  # entries. Cap old generations too so the systemd-boot menu stays short.
  boot.loader.systemd-boot.configurationLimit = 10;

  # InconsolataGo Nerd Font (from the Brewfile). System-level so fontconfig
  # discovers it for ghostty/i3.
  fonts.packages = [ pkgs.nerd-fonts.inconsolata-go ];

  # This is a desktop machine — turn on kenjihash's GUI home-manager layer
  # (ghostty/rofi/i3). Headless machines (e.g. a twincounsel EC2 loop VM) leave
  # this off and get only the core ergonomics (shell/editor/herdr/CLIs/git).
  home-manager.users.kenjihash.kenji.desktop.enable = true;
}
