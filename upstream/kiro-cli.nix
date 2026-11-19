{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  versionCheckHook,
  buildFHSEnv,
  kiro-cli,
  waylandSupport ? stdenv.hostPlatform.isLinux,
}:

let
  version = "3.5.0";
  inherit (stdenv.hostPlatform) system isLinux;
  download = platform: sha256: fetchurl {
    url = "https://prod.download.cli.kiro.dev/stable/${version}/kirocli-${platform}.tar.gz";
    inherit sha256;
  };
  sources = {
    x86_64-linux = download "x86_64-linux" "98f016b746b342d8337a0e937cabecc381037e2e920ea0ffaae649e51ef59d4e";
    aarch64-linux = download "aarch64-linux" "34444fee032944037282c762df4ff6929a51e827dd72d402cb7a8afbecb33e7f";
    aarch64-darwin = download "universal-darwin" "6f26f51fe8b2f26db058e45ad2d4f8bce77a49167b27da2dce6702952a3630db";
  };
  unwrapped = stdenv.mkDerivation {
    pname = if isLinux then "kiro-cli-unwrapped" else "kiro-cli";
    inherit version;
    src = sources.${system};
    sourceRoot = "kirocli";
    strictDeps = true;
    nativeBuildInputs = lib.optional isLinux autoPatchelfHook;
    buildInputs = lib.optional isLinux stdenv.cc.cc.lib;
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 bin/kiro-cli -t "$out/bin"
      runHook postInstall
    '';
    doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
    nativeInstallCheckInputs = [ versionCheckHook ];
    meta = kiro-cli.meta // { platforms = builtins.attrNames sources; };
  };
in
if !lib.versionOlder kiro-cli.version version then
  kiro-cli
else if isLinux then
  buildFHSEnv {
    pname = "kiro-cli";
    inherit version;
    inherit (unwrapped) meta;
    # The TUI extracts a Bun executable that needs the standard Linux loader.
    runScript = lib.getExe unwrapped;
    targetPkgs = pkgs: [ unwrapped pkgs.stdenv.cc.cc.lib ]
      ++ lib.optional waylandSupport pkgs.wl-clipboard;
    passthru = { inherit unwrapped; };
  }
else
  unwrapped
