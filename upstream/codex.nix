# codex, from OpenAI's own release archive rather than built from source.
#
# nixpkgs builds codex with rustPlatform, which means a bump needs a recomputed
# cargoHash and a full uncached Rust compile on every box that converges. The
# fleet wants this CLI current, not built, so this takes the release archive
# upstream already publishes and signs. update.sh records which one.
#
# The daemon manager discovers and copies the complete package using
# codex-package.json beside bin/, codex-path/ and codex-resources/. Keep the
# real entrypoint inside that layout and put the PATH wrapper outside it.
{
  lib,
  stdenvNoCC,
  fetchurl,
  installShellFiles,
  makeBinaryWrapper,
  versionCheckHook,
  autoPatchelfHook,
  stdenv,
  ncurses,
  bubblewrap,
  ripgrep,
  data ? lib.importJSON ./codex.json,
  installShellCompletions ? stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform,
}:

let
  platform =
    data.platforms.${stdenvNoCC.hostPlatform.system}
      or (throw "codex: no upstream release artifact for ${stdenvNoCC.hostPlatform.system}");
in

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "codex";
  inherit (data) version;

  src = fetchurl { inherit (platform) url hash; };

  # The archive unpacks as bin/, codex-path/, codex-resources/ with no single
  # containing directory.
  sourceRoot = ".";

  strictDeps = true;
  __structuredAttrs = true;

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ] ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    ncurses
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/codex $out/bin
    cp -R bin codex-package.json codex-path codex-resources $out/libexec/codex/

    makeWrapper $out/libexec/codex/bin/codex $out/bin/codex --prefix PATH : ${
      lib.makeBinPath ([ ripgrep ] ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ bubblewrap ])
    }

    ${lib.optionalString installShellCompletions ''
      installShellCompletion --cmd codex \
        --bash <($out/bin/codex completion bash) \
        --fish <($out/bin/codex completion fish) \
        --zsh <($out/bin/codex completion zsh)
    ''}

    runHook postInstall
  '';

  # Runs the installed binary and matches its output against `version`, which
  # is what catches an update.sh run that recorded a version the artifact does
  # not actually carry.
  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  meta = {
    description = "Lightweight coding agent that runs in your terminal";
    homepage = "https://github.com/openai/codex";
    changelog = "https://github.com/openai/codex/releases/tag/rust-v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    platforms = lib.attrNames data.platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
