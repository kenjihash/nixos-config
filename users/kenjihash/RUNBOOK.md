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

## Day-to-day rebuilds (after bootstrap)

Edit config in `~/nixos-config` on the VM, then:

```bash
# on the VM:
make switch        # NIXNAME defaults to dev on Linux, no override needed
```
