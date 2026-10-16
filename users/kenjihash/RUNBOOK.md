# dev VM runbook (VMware Fusion, Apple Silicon)

Personal runbook for standing up / re-bootstrapping the local `dev` NixOS VM.
All commands run **from the Mac** unless marked `# on the VM`.

## 0. Host prerequisites (do these first, every fresh VM)

- **Network adapter = Bridged.** VMware Fusion's NAT DNS is broken on macOS
  15.4+ (documented Broadcom bug), so NAT leaves the guest unable to resolve
  DNS in both bootstrap stages. Bridged makes the guest get IP + DNS straight
  from the LAN router. Consequence: the VM lives on the LAN subnet (10.0.0.x),
  not NAT's 192.168.204.x. See the HOST REQUIREMENT note in `machines/dev.nix`.
- Disk bus = **SATA** (aarch64 ISO has no SCSI driver → disk shows as
  `/dev/sda`).

## 1. On the booted NixOS minimal ISO

```bash
sudo su
passwd                 # set root password to: root
ip -4 addr             # note the ethernet IP (10.0.0.x) = <IP>
```

## 2. Partition + generic install

```bash
make vm/bootstrap0 NIXADDR=<IP>
```

Config-independent: partitions `/dev/sda`, installs a generic NixOS, reboots.
After it reboots into the generic install, **re-check the IP** on the VM
console (`ip -4 addr`) — bridged DHCP may hand out a different address.

## 3. Apply the dev config

```bash
make vm/bootstrap NIXNAME=dev NIXADDR=<IP>
```

⚠️ **`NIXNAME=dev` is REQUIRED.** On the Mac (Darwin) `NIXNAME` defaults to
`macbook-pro-m1`; without the override, `vm/switch` tries to build the darwin
config on the VM and fails. (On the VM itself, `NIXNAME` already defaults to
`dev`.)

**This command is EXPECTED TO FAIL at the end, on `vm/secrets`.** That is fine
and intended — `vm/bootstrap` runs `vm/copy` → `vm/switch` → `vm/secrets` →
reboot, and Make stops at the first failing step. By the time `vm/secrets`
errors, **`vm/copy` and `vm/switch` have already succeeded and the config is
live** (you'll see `Done. The new configuration is …nixos-system-dev…` printed
just above the error). `vm/secrets` is Mitchell's GPG+SSH sneakernet rsync; the
`~/.gnupg` half fails because we don't use GPG. We supply the useful (SSH) half
by hand in step 5.

Do **not** run `vm/switch` separately afterward — the switch already happened.

Then reboot manually (the recipe's reboot step was skipped):

```bash
ssh -o PubkeyAuthentication=no -o StrictHostKeyChecking=no root@<IP> reboot
```

## 4. Point ssh at the VM

Edit `~/.ssh/config` → `Host dev` → `HostName <IP>`. `ssh dev` is now keyless
(the live config authorizes the Mac's `~/.ssh/id_ed25519.pub`).

## 5. Supply SSH creds (the working half of `vm/secrets`)

`vm/secrets` only *copies key files*; it does not touch the passphrase. Do the
SSH half manually so the VM can talk to GitHub (clone + commit signing):

```bash
rsync -av --exclude='environment' ~/.ssh/ dev:~/.ssh/
```

```bash
# on the VM (fish shell):
chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_ed25519
eval (ssh-agent -c)          # fish syntax, NOT bash `eval $(ssh-agent)`
ssh-add ~/.ssh/id_ed25519    # enter the key passphrase ONCE per session
```

The key stays passphrase-encrypted on the VM; the passphrase is never stored —
you unlock it with `ssh-add` on use.

## 6. Clone the repo for nvim (LazyVim)

`~/.config/nvim` is an out-of-store symlink to
`~/nixos-config/users/kenjihash/nvim`, so the repo must be checked out at
`~/nixos-config` **on the `kenji` branch** (nvim files live on `kenji`, not the
pristine `main`):

```bash
# on the VM:
git clone git@github.com:kenjihash/nixos-config.git ~/nixos-config
cd ~/nixos-config && git checkout kenji
```

Once `~/nixos-config/users/kenjihash/nvim` exists the dangling symlink resolves
— restart `nvim` and LazyVim loads. No rebuild needed.

### Mermaid previews over SSH and Mosh

Put the cursor in a Mermaid fenced block and press `Space mp` to show or hide
its preview below the source. `Space mm` switches between image and ASCII mode
and clears the current preview. Rendering stays on demand; edits and window
resizes clear stale previews. The Markdown file is never modified by previews.

In a Ghostty SSH session, start Neovim with an explicit image preference:

```bash
env MERMAID_PREVIEW_MODE=image SNACKS_GHOSTTY=true nvim notes.md
```

Image mode sends PNG bytes to the terminal, including when herdr did not inherit
SSH environment variables. Ghostty's inline graphics support is required;
terminals with graphics support but no inline placeholders use a hover float.
Keep `SNACKS_GHOSTTY` scoped to the Ghostty launch.

In the remote shell reached through Mosh on iOS:

```bash
env MERMAID_PREVIEW_MODE=ascii nvim notes.md
```

ASCII mode uses plain text virtual lines and does not probe or send terminal
graphics. Diagrams are sized for the current window's usable width. Diagrams
that still exceed it open in a read-only float with wrapping disabled; use
normal scrolling and `zh`/`zl`, then `q` or Escape to close it.

Without a preference, Neovim starts in image mode. Preferences apply when a new
Neovim process starts; when attaching to an existing herdr/Neovim session from
another client, use `Space mm` to select the appropriate mode.

### Browser Markdown and Mermaid previews over Tailscale

`mdp notes.md` runs go-grip in the foreground on fixed port 8090. `mdp` uses
the existing `fd -e md | fzf` picker (Escape exits quietly); `mdp path/to/dir`
serves that directory's file tree. Paths containing spaces work when quoted.
Keep the process running in your SSH/Mosh session or herdr and stop with Ctrl-C.
The function prints the tailnet root URL and, for a file, its direct preview URL.
The function reads this node's `.Self.DNSName` from `tailscale status --json`
each time it runs, removing the trailing dot to construct the HTTPS URL. There
is no hostname or tailnet suffix to configure, and node renames take effect
automatically. It stops with an error if Tailscale is missing, disconnected,
or cannot provide a DNS name.

Both go-grip and `mdp` live in the portable `hm-core.nix` layer exported as
`homeManagerModules.default`, so consumers such as loop-kenji receive them
after updating their input pin and rebuilding. The consumer must provide a
nixpkgs with `go-grip` and install/configure Tailscale at the host level.

Package: `pkgs.go-grip` **0.9.2** from the existing locked nixos-26.05 input;
no custom derivation or lock-file update. Confirmed with the packaged
`go-grip --help` and its v0.9.2 source:

- `--port 8090` (`-p`) sets the port.
- `--host 127.0.0.1` (`-H`) only sets the advertised URL in this release.
  Its listener is actually `http.ListenAndServe(":8090", ...)` on all addresses.
- `--browser=false` (`-b=false`) prevents opening a browser on the headless VM.
- `--no-reload=false` leaves automatic reload enabled (the default).
- Directory browsing uses `path.Dir(argument)`, so `mdp` appends `/` to directory
  arguments. No directory-mode flag is needed in this version.

The dev config enables the firewall (the shared VM base disables it), preserves
SSH TCP 22 and Mosh UDP 60000–61000, and permits Tailscale's transport UDP port.
TCP **8090 is never opened**. An explicit IPv4/IPv6 raw PREROUTING rule drops
non-loopback traffic to local port 8090 on every interface, including tailscale0,
before Tailscale's INPUT accept rules can bypass the NixOS firewall. Localhost
remains reachable by Tailscale Serve.

`tailscale-serve-mdp.service` declaratively runs
`tailscale serve --bg --yes --https=443 http://127.0.0.1:8090` after tailscaled.
It retries on failure. Serve terminates HTTPS and proxies HTTP and reload
WebSockets to localhost; only the Markdown server runs interactively.
The root HTTPS endpoint is reserved for these previews. Until `mdp` runs, a
proxy error is expected. go-grip also exposes the selected file's containing
directory, so start it in a directory whose contents you intend to preview.

On loop-kenji or another consumer of the portable Home Manager layer, configure
Serve and the firewall in that machine's NixOS config: the shared Home Manager
layer cannot install system services or firewall rules. Use the
`tailscale-serve-mdp` unit and the TCP 8090 protection in `machines/dev.nix` as
the reference, preserving that host's existing network configuration. In
particular, merely omitting 8090 from allowed ports can leave it reachable
through Tailscale's INPUT accept rules with go-grip 0.9.2.

For a host where Serve is managed manually, after protecting port 8090:

```fish
sudo tailscale set --operator=$USER
tailscale serve --bg 8090
```

This uses that host's own MagicDNS name. The same HTTPS certificate and ACL
prerequisites below apply, using the destination tag assigned to that host.

Manual prerequisites:

1. Authenticate the VM with Tailscale if needed (`sudo tailscale up`), and connect
   both the Mac and iPhone to the same tailnet.
2. Enable **MagicDNS** and **HTTPS certificates** in the Tailscale admin console's
   DNS settings. Serve provisions the certificate automatically.
3. In the existing ACL policy, allow **your user-owned devices → the VM's actual
   tag → TCP 443**. For an ACL-style policy, the entry is:

   ```json
   { "action": "accept", "src": ["<your-tailnet-login>"], "proto": "tcp", "dst": ["tag:<vm-tag>:443"] }
   ```

   Replace both placeholders with the tailnet login and the tag already assigned
   to the VM. A tagged destination needs this explicit rule; `autogroup:self`
   does not cover tagged nodes. No ACL policy is changed by this repo, and no
   permission for port 8090 or Funnel is needed.

After rebuilding, start a new fish shell (or `exec fish`) and verify:

1. On the VM, make a sample file and serve it:

   ````fish
   mkdir -p /tmp/mdp-demo
   printf '# Preview\n\n```mermaid\nflowchart LR\n  Mac --> VM\n  iPhone --> VM\n```\n' > /tmp/mdp-demo/README.md
   mdp /tmp/mdp-demo/README.md
   ````

2. Open the printed **File** HTTPS URL on both Mac and iPhone while connected to
   Tailscale. Confirm the Mermaid block renders as a diagram. The printed root
   URL also lets you browse to the file.
3. Edit and save the file from another session, changing a node label. Confirm
   both open browsers reload automatically and show the changed diagram.
4. Try `mdp`, cancel the picker, then try `mdp /tmp/mdp-demo` and browse the directory.
5. Inspect the VM's proxy and firewall:

   ```bash
   systemctl status tailscale-serve-mdp
   tailscale serve status
   ss -ltn 'sport = :8090'
   sudo iptables -t raw -C PREROUTING ! -i lo -p tcp --dport 8090 -m addrtype --dst-type LOCAL -j DROP
   sudo ip6tables -t raw -C PREROUTING ! -i lo -p tcp --dport 8090 -m addrtype --dst-type LOCAL -j DROP
   ```

   The wildcard listener is expected for v0.9.2. Both firewall checks should
   succeed. From the Mac, `curl --connect-timeout 3 http://<VM-LAN-IP>:8090/`
   and the same command with its Tailscale IP should fail while HTTPS works.
   Check IPv6 too if available. Confirm SSH and Mosh still connect.

If HTTPS was enabled after the rebuild, restart the proxy with
`sudo systemctl restart tailscale-serve-mdp`. To remove it permanently, remove
the unit from the config, rebuild, then run `sudo tailscale serve --https=443 off`:
`--bg` state persists in tailscaled even after the oneshot is stopped.

References: [go-grip v0.9.2 source](https://github.com/chrishrb/go-grip/tree/v0.9.2),
[Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve),
[ACL syntax](https://tailscale.com/docs/reference/syntax/policy-file).

## Day-to-day rebuilds (after bootstrap)

Edit config in `~/nixos-config` on the VM, then:

```bash
# on the VM:
make switch        # NIXNAME defaults to dev on Linux, no override needed
```
