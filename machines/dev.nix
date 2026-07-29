{ ... }: {
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
}
