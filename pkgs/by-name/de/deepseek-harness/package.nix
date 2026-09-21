{
  lib,
  bashInteractive,
  bubblewrap,
  buildNpmPackage,
  fetchurl,
  importNpmLock,
  makeWrapper,
  nodejs_22,
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
  src = runCommand "${pname}-source" { nativeBuildInputs = [ nodejs_22 ]; } ''
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

  # Use importNpmLock instead of npmDepsHash
  npmDeps = importNpmLock {
    npmRoot = src;
  };
  
  # Must use importNpmLock.npmConfigHook
  npmConfigHook = importNpmLock.npmConfigHook;

  nodejs = nodejs_22;  # Pin Node.js version

  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    # /bin/bash does not exist on NixOS (issue #8086)
    substituteInPlace \
      $out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-terminal-bash/lib/index.js \
      --replace-fail '"/bin/bash"' '"${lib.getExe bashInteractive}"'

    # The runtime profile resolver drives Node's internal module loader through
    # the prebuilt `node-addon-require-builtin` N-API binary, which locates V8's
    # `builtin_module_require` getter by pattern-matching the machine code of a
    # known Node build. nixpkgs compiles Node with GCC, whose codegen for that
    # getter differs from the upstream release binaries (an extra `xor edi,edi`
    # before `ret`), so every `requireBuiltin` call fails with
    # `Unsupported/no-getter (x64 sysv getter is not a recognized this->field
    # accessor)` and boot aborts. Fall back to the pure-JS `link` resolution
    # mode, which was upstream's default before 0.1.6-alpha.2 (commit
    # 9ddef327a) and needs no native addon. This package ships the compiled
    # bundle, so patch the output chunk (its hash suffix changes between
    # releases, hence the glob).
    substituteInPlace \
      $out/lib/node_modules/@deepseek-ai/dsh/lib/profile-boot-*.js \
      --replace-fail \
        'options.resolutionMode ?? "runtime"' \
        'options.resolutionMode ?? "link"'

    rm $out/bin/dsh
    # dsh-sandbox-local probes `bwrap` from PATH for its preferred Linux
    # sandbox backend (chain: bwrap, then landlock).
    makeWrapper ${lib.getExe nodejs_22} $out/bin/dsh \
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
