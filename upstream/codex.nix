# codex, from OpenAI's own release archive rather than built from source.
#
# nixpkgs builds codex with rustPlatform, which means a bump needs a recomputed
# cargoHash and a full uncached Rust compile on every box that converges. These
# machines want this CLI current, not built, so this takes the release archive
# upstream already publishes and signs. update.sh records which one.
#
# `codex-package-*` is upstream's self-contained layout: the two binaries below
# plus a bundled ripgrep, bubblewrap, zsh and a gstreamer voice runtime. Only
# the binaries are installed. They are static-pie and need no patching, while
# the bundled libraries are linked against a loader NixOS does not have --
# ripgrep and bubblewrap come from nixpkgs on PATH instead, which is the same
# pair nixpkgs' own build wraps codex with.
{
  lib,
  stdenvNoCC,
  fetchurl,
  installShellFiles,
  makeBinaryWrapper,
  versionCheckHook,
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
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 bin/codex $out/bin/codex
    # Out-of-process V8 execution; codex resolves it next to its own binary.
    install -Dm755 bin/codex-code-mode-host $out/bin/codex-code-mode-host

    wrapProgram $out/bin/codex --prefix PATH : ${
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
