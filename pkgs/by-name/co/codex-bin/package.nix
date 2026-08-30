{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  bubblewrap,
}:

let
  version = "0.151.0";
  target = "x86_64-unknown-linux-musl";
in
stdenvNoCC.mkDerivation {
  pname = "codex-bin";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}-linux-x64.tgz";
    hash = "sha256-s7zywRaT18gVXeY33WViuhnZFroTRxp8hzfeVeUyj8Y=";
  };

  sourceRoot = "package/vendor/${target}";

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/codex-resources" "$out/codex-path"
    cp bin/codex bin/codex-code-mode-host "$out/bin/"
    cp -r codex-resources/. "$out/codex-resources/"
    cp -r codex-path/. "$out/codex-path/"
    cp codex-package.json "$out/"

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/codex" \
      --prefix PATH : ${lib.makeBinPath [ bubblewrap ]}
  '';

  meta = {
    description = "OpenAI Codex CLI binary distribution";
    homepage = "https://github.com/openai/codex";
    changelog = "https://github.com/openai/codex/releases/tag/rust-v${version}";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
