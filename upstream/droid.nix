{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  stdenv,
  ripgrep,
  makeWrapper,
  versionCheckHook,
  writableTmpDirAsHomeHook,
  data ? lib.importJSON ./droid.json,
}:

let
  platform =
    data.platforms.${stdenvNoCC.hostPlatform.system}
      or (throw "droid: no upstream release artifact for ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "droid";
  inherit (data) version;

  src = fetchurl { inherit (platform) url hash; };

  strictDeps = true;
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  # Bun's embedded application payload must remain attached to the binary.
  dontStrip = true;

  nativeBuildInputs = [ makeWrapper ]
    ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src" "$out/libexec/droid/droid"
    makeWrapper "$out/libexec/droid/droid" "$out/bin/droid" \
      --prefix PATH : ${lib.makeBinPath [ ripgrep ]}

    runHook postInstall
  '';

  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  nativeInstallCheckInputs = [ versionCheckHook writableTmpDirAsHomeHook ];
  versionCheckProgramArg = "--version";
  versionCheckKeepEnvironment = [ "HOME" ];

  meta = {
    description = "Factory's coding agent for the terminal";
    homepage = "https://factory.ai";
    license = lib.licenses.unfree;
    mainProgram = "droid";
    platforms = lib.attrNames data.platforms;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
