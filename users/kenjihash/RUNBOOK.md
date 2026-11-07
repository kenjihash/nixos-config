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

`mdp notes.md` runs grip-live-diff in the foreground on fixed port 8090. `mdp` uses
the existing `fd -e md | fzf` picker (Escape exits quietly); `mdp path/to/dir`
serves that directory's file tree. Paths containing spaces work when quoted.
Keep the process running in your SSH/Mosh session or herdr and stop with Ctrl-C.
The function prints the tailnet root URL and, for a file, its direct preview URL.
The function reads this node's `.Self.DNSName` from `tailscale status --json`
each time it runs, removing the trailing dot to construct the HTTPS URL. There
is no hostname or tailnet suffix to configure, and node renames take effect
automatically. It stops with an error if Tailscale is missing, disconnected,
or cannot provide a DNS name.

`kenji.mdp.httpsPort` controls the printed URL's port and defaults to 443 for
portable consumers. `dev` sets it to 7297 and uses that same value for its
Serve mapping. Configure the option to match Serve on any other host; the
`loop-kenji` team profile supplies its own `mdp` wrapper and port.

Both grip-live-diff and `mdp` live in the portable `hm-core.nix` layer exported as
`homeManagerModules.default`, so consumers such as loop-kenji receive them
after updating their input pin and rebuilding. The package is imported directly
from `grip-live-diff.nix`; consumers need no custom overlay. They must still
install/configure Tailscale and protect TCP 8090 at the host level.

Package: grip-live-diff **1.8.0**, using checksum-pinned upstream binaries for
ARM64/x86-64 Linux and macOS. Upgrade the version and asset hashes together in
`grip-live-diff.nix`, then rebuild; `grip-live-diff update` cannot replace a
binary in the read-only Nix store. No flake input or lock-file update is needed.

- `--port 8090` (`-p`) sets the port.
- `--host 127.0.0.1` (`-H`) only sets the advertised URL in this release.
  Its listener is actually `http.ListenAndServe(":8090", ...)` on all addresses.
- `--browser=false` (`-b=false`) prevents opening a browser on the headless VM.
- `--no-reload=false` leaves automatic reload enabled (the default).
- Upstream serves a directory argument from its parent, even with a trailing
  slash. `mdp directory` instead starts the server inside the chosen directory
  with no file argument, keeping the HTTPS root at that directory. This happens
  in a child shell, preserving the calling shell's working directory. File
  arguments serve their containing directory, with an encoded direct file URL.

Use the toolbar's **±** button (`d`) to enable word-level diffs. Choose
**since open** (`1`), **last edit** (`2`), or **HEAD** (`3`, requires a committed
file in a Git worktree). **Mark as read** resets the first two references; the
HEAD reference follows Git. These references are held by the server process,
so restarting it resets the since-open and last-edit history.

For inline feedback, enable the pencil, select text, and add a comment. Adding
a comment leaves the Markdown unchanged and writes companion files next to it:

| For `notes.md` | Purpose |
| --- | --- |
| `notes.annotations.json5` | Selected passages, reader/agent threads, and completion status. |
| `notes.annotations.d/<hash>.md` | Full document snapshots for versions referenced by comments. |
| `notes.annotations.ready` | Temporary batch signal after pressing **Go** in manual mode. |

These are writable files on the server, including when the browser is on a
phone. The document's directory must be writable to save comments and snapshots.
The server removes snapshots when no comments reference them; marking a comment
done keeps its thread and referenced snapshot. Generated files can appear in
`git status`; keep them untracked for personal feedback or commit them for shared
review. Do not symlink them into the Nix store.

Tell an agent to handle `notes.annotations.json5`. Its header describes the
protocol: lock the sidecar with an exclusive `flock`, preserve reader messages,
append replies, update passage anchors as needed, and mark handled entries done.
In **manual** mode, comments accumulate until **Go** creates the ready file. An
agent following the protocol claims that batch and deletes the ready file last.
The preview does not launch an agent: monitoring/handling these files needs an
explicit instruction to an existing agent. Switching back to **auto** removes
the stale ready signal.

Width, theme, and reload-hold preferences are writable runtime settings in the
user config directory (`$XDG_CONFIG_HOME/grip-live-diff/settings.json`, normally
`~/.config/grip-live-diff/settings.json` on Linux; on macOS,
`~/Library/Application Support/grip-live-diff/settings.json`). Leave this file
unmanaged by Home Manager so changes from the browser can persist.

The dev config enables the firewall (the shared VM base disables it), preserves
SSH TCP 22 and Mosh UDP 60000–61000, and permits Tailscale's transport UDP port.
TCP **8090 is never opened**. An explicit IPv4/IPv6 raw PREROUTING rule drops
non-loopback traffic to local port 8090 on every interface, including tailscale0,
before Tailscale's INPUT accept rules can bypass the NixOS firewall. Localhost
remains reachable by Tailscale Serve.

`tailscale-serve-mdp.service` declaratively runs
`tailscale serve --bg --yes --https=7297 http://127.0.0.1:8090` after tailscaled.
It retries on failure. Serve terminates HTTPS and proxies HTTP and reload
WebSockets to localhost; only the Markdown server runs interactively.
The HTTPS 7297 endpoint is reserved for these previews. Until `mdp` runs, a
proxy error is expected. grip-live-diff also exposes the selected file's containing
directory, so start it in a directory whose contents you intend to preview.

On loop-kenji or another consumer of the portable Home Manager layer, configure
Serve and the firewall in that machine's NixOS config: the shared Home Manager
layer cannot install system services or firewall rules. Use the
`tailscale-serve-mdp` unit and the TCP 8090 protection in `machines/dev.nix` as
the reference, preserving that host's existing network configuration. In
particular, merely omitting 8090 from allowed ports can leave it reachable
through Tailscale's INPUT accept rules with grip-live-diff 1.8.0.

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

2. Open the printed **File** HTTPS URL on both Mac and iPhone while connected to
   Tailscale. Confirm the Mermaid block renders as a diagram. The printed root
   URL also lets you browse to the file.
3. Edit and save the file from another session, changing a node label. Confirm
   both open browsers reload automatically and show the changed diagram.
4. Try `mdp`, cancel the picker, then try `mdp /tmp/mdp-demo` and browse the
   directory. Confirm the root lists only that directory and the calling shell's
   working directory is unchanged after Ctrl-C. Also try quoted paths with spaces.
5. Enable diffs, edit prose, and check since-open/last-edit highlights and
   **Mark as read**. In a committed Git worktree, check **HEAD** too. Add a
   comment and verify its sidecar and snapshot, then have an agent reply under
   the sidecar lock. Check that the browser updates the thread. In manual mode,
   press **Go** and verify the ready file is created and removed after handling.
   Change width/theme and confirm they persist after restarting the server.
   Exercise these writes through HTTPS as well as reloads: an HTTP 403 on a
   write can indicate a proxy Host/Origin mismatch.
6. Inspect the VM's proxy and firewall:

   ```bash
   systemctl status tailscale-serve-mdp
   tailscale serve status
   ss -ltn 'sport = :8090'
   sudo iptables -t raw -C PREROUTING ! -i lo -p tcp --dport 8090 -m addrtype --dst-type LOCAL -j DROP
   sudo ip6tables -t raw -C PREROUTING ! -i lo -p tcp --dport 8090 -m addrtype --dst-type LOCAL -j DROP
   ```

   The wildcard listener is expected for v1.8.0. Both firewall checks should
   succeed. From the Mac, `curl --connect-timeout 3 http://<VM-LAN-IP>:8090/`
   and the same command with its Tailscale IP should fail while HTTPS works.
   Check IPv6 too if available. Confirm SSH and Mosh still connect.

If HTTPS was enabled after the rebuild, restart the proxy with
`sudo systemctl restart tailscale-serve-mdp`. To remove it permanently, remove
the unit from the config, rebuild, then run `sudo tailscale serve --https=7297 off`:
`--bg` state persists in tailscaled even after the oneshot is stopped.

References: [grip-live-diff v1.8.0 usage](https://github.com/babs/grip-live-diff/blob/v1.8.0/README.md),
[release assets](https://github.com/babs/grip-live-diff/releases/tag/v1.8.0),
[Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve),
[ACL syntax](https://tailscale.com/docs/reference/syntax/policy-file).

## Day-to-day rebuilds (after bootstrap)

Edit config in `~/nixos-config` on the VM, then:

```bash
# on the VM:
make switch        # NIXNAME defaults to dev on Linux, no override needed
```
