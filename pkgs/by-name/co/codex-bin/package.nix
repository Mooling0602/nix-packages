{
  lib,
  stdenvNoCC,
  fetchurl,
  bubblewrap,
}:

let
  version = "0.167.0";
  target = "x86_64-unknown-linux-musl";
in
stdenvNoCC.mkDerivation {
  pname = "codex-bin";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}-linux-x64.tgz";
    hash = "sha256-Lcmqhxq7UTw1OdINAl9wH68ZdMRu6Qa9o6Hh9QJtRDQ=";
  };

  sourceRoot = "package/vendor/${target}";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/codex-resources" "$out/codex-path"
    cp bin/codex bin/codex-code-mode-host "$out/bin/"
    cp -r codex-resources/. "$out/codex-resources/"
    cp -r codex-path/. "$out/codex-path/"
    cp codex-package.json "$out/"

    # Expose bubblewrap through codex-path (which the CLI prepends to PATH at
    # runtime) instead of wrapping "$out/bin/codex". Codex verifies that the
    # entrypoint bytes of its package match the running executable, so a shell
    # wrapper breaks `codex app-server daemon` and `codex update --from-cli`.
    # Symlinks are rejected by that package validation, hence the copy.
    cp ${lib.getExe bubblewrap} "$out/codex-path/bwrap"

    runHook postInstall
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
