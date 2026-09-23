#!/usr/bin/env bash
# Refresh the pinned upstream release data for the fast-lane agent CLIs.
#
# These four CLIs are distributed by their vendors as prebuilt binaries, and
# nixpkgs redistributes those same bytes unchanged. Taking the vendor's own
# release feed instead of waiting for a channel advance costs nothing in
# provenance -- the checksum is the vendor's either way -- and removes the
# nixpkgs maintainer, review, and Hydra stages from between a release and these
# machines. The agent-CLI overlay in ../flake.nix reads what this writes.
#
# Kept in step with twincounsel/nix/upstream/update.sh, which carries the same
# four feeds so that repo can stand alone without this one.
#
# opencode and pi-coding-agent are deliberately absent: nixpkgs builds both
# from source with vendored dependency trees, so there is no prebuilt artifact
# to pin and a fast lane for them would mean re-implementing that vendoring.
# They stay on the channel.
#
# Needs: bash, curl, jq, nix. Writes *.json beside itself; commit the result.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

note() { printf '%s\n' "$*" >&2; }

# Records the version and, per Nix system, the exact artifact to fetch. Every
# hash is SRI so Nix consumes it verbatim.
emit() {
  local file=$1 json=$2
  printf '%s\n' "$json" | jq --sort-keys . >"$file"
  note "  wrote $file ($(jq -r .version "$file"))"
}

# claude-code -- the vendor publishes a manifest carrying the version, the
# per-platform binary name and its sha256. nixpkgs' own package reads exactly
# this file, so it is stored verbatim rather than reshaped, and the package
# takes it through its `manifest` argument.
update_claude_code() {
  local base=https://downloads.claude.ai/claude-code-releases version manifest
  version=$(curl -fsSL "$base/latest")
  note "claude-code: upstream $version"
  manifest=$(curl -fsSL "$base/$version/manifest.zst.json")
  jq -e --arg v "$version" '.version == $v and (.platforms | length > 0)' >/dev/null <<<"$manifest" \
    || { note "claude-code: manifest does not describe $version"; return 1; }
  emit claude-code.json "$manifest"
}

# antigravity-cli -- the release manifest carries a full URL and a sha512 per
# platform. The URL embeds a build id that is not derivable from the version,
# which is why the whole URL is stored rather than a version to interpolate.
update_antigravity_cli() {
  local base=https://storage.googleapis.com/antigravity-public/antigravity-cli
  local version manifest out sys key url hex
  version=$(curl -fsSL "$base/latest")
  note "antigravity-cli: upstream $version"
  manifest=$(curl -fsSL "$base/$version/manifest.json")
  out=$(jq -n --arg v "$version" '{version: $v, platforms: {}}')
  for pair in x86_64-linux:linux-x64 aarch64-linux:linux-arm aarch64-darwin:darwin-arm; do
    sys=${pair%%:*}
    key=${pair##*:}
    url=$(jq -er --arg k "$key" '.platforms[$k].url' <<<"$manifest")
    hex=$(jq -er --arg k "$key" '.platforms[$k].sha512' <<<"$manifest")
    out=$(jq --arg s "$sys" --arg u "$url" --arg h "$(nix hash convert --hash-algo sha512 --to sri "$hex")" \
      '.platforms[$s] = {url: $u, hash: $h}' <<<"$out")
  done
  emit antigravity-cli.json "$out"
}

# codex -- OpenAI signs and publishes a SHA256SUMS file covering the
# `codex-package-*` archives, so a bump needs no download at all. That archive
# is the self-contained layout: upstream/codex.nix installs the two static
# binaries from it and ignores the bundled runtime beside them.
update_codex() {
  local repo=https://github.com/openai/codex tag version sums out sys triple asset hex
  tag=$(curl -fsSL https://api.github.com/repos/openai/codex/releases/latest | jq -er .tag_name)
  version=${tag#rust-v}
  note "codex: upstream $version ($tag)"
  sums=$(curl -fsSL "$repo/releases/download/$tag/codex-package_SHA256SUMS")
  out=$(jq -n --arg v "$version" '{version: $v, platforms: {}}')
  for pair in \
    x86_64-linux:x86_64-unknown-linux-musl \
    aarch64-linux:aarch64-unknown-linux-musl \
    x86_64-darwin:x86_64-apple-darwin \
    aarch64-darwin:aarch64-apple-darwin; do
    sys=${pair%%:*}
    triple=${pair##*:}
    asset="codex-package-$triple.tar.gz"
    hex=$(awk -v a="$asset" '$2 == a { print $1 }' <<<"$sums")
    [ -n "$hex" ] || { note "codex: $asset absent from SHA256SUMS"; return 1; }
    out=$(jq --arg s "$sys" --arg u "$repo/releases/download/$tag/$asset" \
      --arg h "$(nix hash convert --hash-algo sha256 --to sri "$hex")" \
      '.platforms[$s] = {url: $u, hash: $h}' <<<"$out")
  done
  emit codex.json "$out"
}

# grok-build -- xAI publishes no checksums, so each artifact is fetched to hash
# it. That is ~170MB per platform, which is why a hash already recorded for the
# same URL is reused instead of being downloaded again.
update_grok_build() {
  local version out sys platform url hex prev=grok-build.json
  version=$(curl -fsSL https://x.ai/cli/stable)
  note "grok-build: upstream $version"
  out=$(jq -n --arg v "$version" '{version: $v, platforms: {}}')
  for pair in x86_64-linux:linux-x86_64 aarch64-linux:linux-aarch64 aarch64-darwin:macos-aarch64; do
    sys=${pair%%:*}
    platform=${pair##*:}
    url="https://x.ai/cli/grok-$version-$platform"
    hex=""
    if [ -f "$prev" ]; then
      hex=$(jq -r --arg s "$sys" --arg u "$url" \
        '.platforms[$s] | select(. != null and .url == $u) | .hash' "$prev")
    fi
    if [ -z "$hex" ]; then
      note "  prefetching $url"
      hex=$(nix hash convert --hash-algo sha256 --to sri "$(nix-prefetch-url "$url")")
    fi
    out=$(jq --arg s "$sys" --arg u "$url" --arg h "$hex" \
      '.platforms[$s] = {url: $u, hash: $h}' <<<"$out")
  done
  emit grok-build.json "$out"
}

packages=("$@")
[ ${#packages[@]} -gt 0 ] || packages=(claude-code antigravity-cli codex grok-build)

for pkg in "${packages[@]}"; do
  case $pkg in
    claude-code) update_claude_code ;;
    antigravity-cli) update_antigravity_cli ;;
    codex) update_codex ;;
    grok-build) update_grok_build ;;
    *) note "unknown package: $pkg"; exit 1 ;;
  esac
done
