{
  lib,
  bashInteractive,
  bubblewrap,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  nodejs,
  runCommand,
  versionCheckHook,
}:

let
  pname = "deepseek-harness";

  versionData = lib.importJSON ./hashes.json;
  inherit (versionData) version;

  # package-lock.json (maintained in this directory via update.sh) is injected
  # into the npm tarball source so buildNpmPackage resolves the exact tree.
  # The lockfile covers production dependencies only (dsh lists unreleased
  # workspace packages among its devDependencies), so devDependencies is
  # stripped from the manifest to keep `npm ci` in sync.
  src = runCommand "${pname}-source" { nativeBuildInputs = [ nodejs ]; } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${version}.tgz";
        hash = versionData.sourceHash;
      }
    } -C $out --strip-components=1
    cp ${./package-lock.json} $out/package-lock.json
    node -e 'const fs=require("fs");const f=process.argv[1];const p=JSON.parse(fs.readFileSync(f));delete p.devDependencies;fs.writeFileSync(f,JSON.stringify(p,null,2)+"\n")' $out/package.json
  '';

in
buildNpmPackage {
  inherit pname version src;

  npmDepsFetcherVersion = 2;
  npmDepsHash = versionData.npmDepsHash;

  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    # /bin/bash does not exist on NixOS (issue #8086)
    substituteInPlace \
      $out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-terminal-bash/lib/index.js \
      --replace-fail '"/bin/bash"' '"${lib.getExe bashInteractive}"'

    rm $out/bin/dsh
    # dsh-sandbox-local probes `bwrap` from PATH for its preferred Linux
    # sandbox backend (chain: bwrap, then landlock).
    makeWrapper ${lib.getExe nodejs} $out/bin/dsh \
      --argv0 dsh \
      --prefix PATH : ${lib.makeBinPath [ bubblewrap ]} \
      --add-flags "--expose-internals" \
      --add-flags "$out/lib/node_modules/@deepseek-ai/dsh/lib/bin.js"
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
  ];
  versionCheckProgramArg = "--version";

  meta = {
    description = "Open-source agent harness and CLI developed by DeepSeek AI";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    changelog = "https://github.com/deepseek-ai/deepseek-harness/releases";
    downloadPage = "https://www.npmjs.com/package/@deepseek-ai/dsh";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [
      binaryBytecode
      fromSource
    ];
    maintainers = [ ];
    mainProgram = "dsh";
    platforms = lib.platforms.all;
  };
}
