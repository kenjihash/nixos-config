# dev VM runbook (VMware Fusion, Apple Silicon)

Personal runbook for standing up / re-bootstrapping the local `dev` NixOS VM.
All commands run **from the Mac** unless marked `# on the VM`.

## Shell environment

The portable Home Manager profile adds `~/.local/bin` to the session path.
The local `dev` profile also enables `kenji.direnvInstant.enable`, which loads
direnv environments asynchronously while keeping nix-direnv's cache. The
exported module and standalone profiles leave this option off by default.

After applying the configuration, start a new fish shell and enter a project
with an allowed `.envrc`. Check that the expected tools and environment appear
once direnv finishes, and that leaving the project unloads the environment.
The prompt can return before the project environment is ready.

To return to synchronous hooks, set `kenji.direnvInstant.enable = false;` in
`users/kenjihash/home-manager.nix` and apply the configuration again.

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

### Rex remote terminal server

`dev` enables the socket-activated Rex login server through the upstream NixOS
module, using the same preview release pinned by `twincounsel/nix`. It installs
the CLI, terminfo and SSH guard system-wide. Only
`tailscale:kenji@twincounsel.com` can open sessions as the local `kenjihash`
account, which is also the default account for that principal. The existing
Tailscale enrollment supplies identity and HTTPS; no separate Rex auth key is
needed. The VM must be connected to the same tailnet as the client.

Rex owns `https://<this-node's-MagicDNS-name>/` on port 443. Markdown previews
use HTTPS 7297. Before the first rebuild, migrate an existing Markdown route:

```bash
sudo tailscale serve --bg --yes --https=7297 http://127.0.0.1:8090
sudo tailscale serve status
```

Confirm HTTPS 7297 proxies to `http://127.0.0.1:8090`. If HTTPS 443 also points
to that old Markdown endpoint, remove just that route with
`sudo tailscale serve --https=443 off`. Preserve unrelated Serve routes and
resolve other uses of port 443 before rebuilding. Then apply with
`make switch NIXNAME=dev` on the VM.

In Rex for Mac, choose **Add Remote Host…** and enter the VM's HTTPS URL.
Alternatively, run `rex -S https://<this-node's-MagicDNS-name> ls` from a client.
Inspect with `systemctl status rex-login-server.socket rex-tailscale-serve`,
`journalctl -u rex-login-server`, and `tailscale serve status`.

The server is configured only in `machines/dev.nix`, and its module is imported
only by `users/kenjihash/nixos.nix`. Importing `homeManagerModules.default` on
`loop-kenji` installs no Rex package or service and adds no account policy;
the team flake continues to own those. To disable Rex locally, remove the
`services.rex.loginServer` block in `machines/dev.nix`. The upstream options
default to off. To use the package independently, run `nix build .#rex`;
update the pin with `nix flake update rex`.

See [Rex's NixOS installation](https://www.superlogical.com/rex/docs/linux/installation#nix-and-nixos)
and [remote access](https://www.superlogical.com/rex/docs/linux/remote-access#nixos).

### Browser Markdown and Mermaid previews over Tailscale

`mdp notes.md` runs Crit on fixed loopback port 8090. `mdp` uses the
`fd -e md | fzf --multi` picker (Tab selects multiple files, Enter opens the
review, Escape exits quietly). `mdp plan.md api-spec.md` reviews selected files
together; `mdp path/to/dir` loads that directory recursively into a review.
Paths containing spaces work when quoted. Keep the CLI running in your
SSH/Mosh session or herdr and stop with Ctrl-C. Stop the previous preview before
starting another on the same port; `crit stop` from that project also stops a
single remaining session.

The function prints the tailnet root URL, where Crit displays the review.
It reads this node's `.Self.DNSName` from `tailscale status --json` each time,
removing the trailing dot. Node renames take effect automatically. It stops
with an error if Tailscale is missing, disconnected, or cannot provide a DNS name.
`kenji.mdp.httpsPort` defaults to 443 for portable consumers; `dev` sets it to
7297 to match Serve. The `loop-kenji` team profile supplies its own `mdp` wrapper
and will need the same backend change separately.

Crit and `mdp` live in the portable `hm-core.nix` layer exported as
`homeManagerModules.default`. The local `crit.nix` package pins **0.23.2** and
upstream SHA-256 digests for ARM64/x86-64 Linux and macOS. No overlay or new flake
input is needed. Upgrade the version and asset hashes together, then rebuild.
The prior `grip-live-diff.nix` package remains available as a reference.

The wrapper passes `--port 8090 --host 127.0.0.1 --no-open`, plus
`--public-url` with the printed HTTPS URL and `--allow-unauthenticated-network`.
Crit actually binds to loopback. The public URL allows the proxy hostname
through Crit's Host validation; the acknowledgment flag is required even with
a loopback listener when advertising a public URL. Tailscale controls access.
The existing Serve mapping and firewall rules remain in place.

Markdown and Mermaid render in the review. When a document changes during a
review, click **Reload** in Crit's notification. Diffs compare review rounds;
the prior Grip since-open/last-edit/HEAD controls are not part of this workflow.
Use **Finish Review** to hand feedback to an agent, or **Approve** when finished.

Comments and snapshots live under `~/.crit/reviews/<session>/`, rather than Grip's
adjacent annotation sidecars. `crit status` shows active session IDs and paths;
`crit comments --session <id> --json` reads unresolved feedback. Give an existing
agent that session or review path. Crit does not launch an agent by default.
Agent integrations can be installed separately with `crit install <agent>`.
Approval stops the review daemon and, by default, removes the review file; set
`"cleanup_on_approve": false` in `~/.crit.config.json` to preserve review history.
Do not manage writable review files as Nix-store symlinks.

Prefer individual files or directories inside Git repositories.
In 0.23.2, a directory outside Git with nested documents can choose the first
nested file's parent as its review root. Sibling paths then become absolute,
which the comment CLI rejects. Browser comments still work in that case.

The dev config enables the firewall (the shared VM base disables it), preserves
SSH TCP 22 and Mosh UDP 60000–61000, and permits Tailscale's transport UDP port.
TCP **8090 is never opened**. An explicit IPv4/IPv6 raw PREROUTING rule drops
non-loopback traffic to local port 8090 on every interface, including tailscale0,
before Tailscale's INPUT accept rules can bypass the NixOS firewall. Localhost
remains reachable by Tailscale Serve.

`tailscale-serve-mdp.service` declaratively runs
`tailscale serve --bg --yes --https=7297 http://127.0.0.1:8090` after tailscaled.
It retries on failure. Serve terminates HTTPS and proxies HTTP and review
event streams to localhost; only the Markdown server runs interactively.
The HTTPS 7297 endpoint is reserved for these previews. Until `mdp` runs, a
proxy error is expected. Start reviews in a directory whose contents you intend
to make available to devices with access to this endpoint.

On loop-kenji or another consumer of the portable Home Manager layer, configure
Serve and the firewall in that machine's NixOS config: the shared Home Manager
layer cannot install system services or firewall rules. Use the
`tailscale-serve-mdp` unit and the TCP 8090 protection in `machines/dev.nix` as
the reference, preserving that host's existing network configuration. In
particular, retain the explicit port protection when testing other preview
servers that may bind to all addresses.

For a host where Serve is managed manually, after protecting port 8090:

```fish
sudo tailscale set --operator=$USER
tailscale serve --bg --https=7297 http://127.0.0.1:8090
```

Set `kenji.mdp.httpsPort = 7297;` in that host's Home Manager config as well.
This uses that host's own MagicDNS name. The same HTTPS certificate and ACL
prerequisites below apply, using the destination tag assigned to that host.

Manual prerequisites:

1. Authenticate the VM with Tailscale if needed (`sudo tailscale up`), and connect
   both the Mac and iPhone to the same tailnet.
2. Enable **MagicDNS** and **HTTPS certificates** in the Tailscale admin console's
   DNS settings. Serve provisions the certificate automatically.
3. In the existing ACL policy, allow **your user-owned devices → the VM's actual
   tag → TCP 443 for Rex and TCP 7297 for Markdown**. For an ACL-style policy,
   the entry is:

   ```json
   { "action": "accept", "src": ["<your-tailnet-login>"], "proto": "tcp", "dst": ["tag:<vm-tag>:443", "tag:<vm-tag>:7297"] }
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

2. Open the printed **Tailnet** HTTPS URL on Mac and iPhone while connected to
   Tailscale. Confirm the Mermaid block renders as a diagram.
3. Edit and save the file from another session, changing a node label. Click
   **Reload** in each browser and confirm the diagram changes.
4. Try `mdp`, cancel the picker, then try `mdp /tmp/mdp-demo`. Confirm the review
   lists the document and the calling shell's working directory is unchanged
   after Ctrl-C. Also try quoted paths with spaces.
5. Add a comment through HTTPS and read it with `crit comments --session <id>
   --json` from another shell. Have an agent handle the feedback, then review
   the next round and try the diff view. An HTTP 403 can indicate a missing or
   mismatched `--public-url`.
6. Inspect the VM's proxy and firewall:

   ```bash
   systemctl status tailscale-serve-mdp
   tailscale serve status
   ss -ltn 'sport = :8090'
   sudo iptables -t raw -C PREROUTING ! -i lo -p tcp --dport 8090 -m addrtype --dst-type LOCAL -j DROP
   sudo ip6tables -t raw -C PREROUTING ! -i lo -p tcp --dport 8090 -m addrtype --dst-type LOCAL -j DROP
   ```

   The listener should be `127.0.0.1:8090`. Both firewall checks should
   succeed. From the Mac, `curl --connect-timeout 3 http://<VM-LAN-IP>:8090/`
   and the same command with its Tailscale IP should fail while HTTPS works.
   Check IPv6 too if available. Confirm SSH and Mosh still connect.

If HTTPS was enabled after the rebuild, restart the proxy with
`sudo systemctl restart tailscale-serve-mdp`. To remove it permanently, remove
the unit from the config, rebuild, then run `sudo tailscale serve --https=7297 off`:
`--bg` state persists in tailscaled even after the oneshot is stopped.

References: [Crit v0.23.2 usage](https://github.com/tomasz-tomczyk/crit/blob/v0.23.2/README.md),
[release assets](https://github.com/tomasz-tomczyk/crit/releases/tag/v0.23.2),
[Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve),
[ACL syntax](https://tailscale.com/docs/reference/syntax/policy-file).

## Day-to-day rebuilds (after bootstrap)

Edit config in `~/nixos-config` on the VM, then:

```bash
# on the VM:
make switch        # NIXNAME defaults to dev on Linux, no override needed
```
