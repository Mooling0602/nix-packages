{
  lib,
  bashInteractive,
  bubblewrap,
  fetchFromGitHub,
  fetchPnpmDeps,
  fetchurl,
  makeWrapper,
  nodejs-slim,
  nodejs_24,
  pnpmConfigHook,
  stdenv,
  versionCheckHook,
}:

let
  pname = "deepseek-harness-git";

  versionData = lib.importJSON ./hashes.json;
  inherit (versionData) version rev;

  src = fetchFromGitHub {
    owner = "deepseek-ai";
    repo = "deepseek-harness";
    inherit rev;
    hash = versionData.srcHash;
  };

  # Upstream maintains pnpm-lock.yaml with the `packageManager` pin from the
  # root package.json (currently pnpm@${versionData.pnpmVersion}). nixpkgs
  # pnpm 11.22 changed offline / supply-chain behaviour in ways that reject
  # these lockfiles, so run the exact pinned pnpm through nixpkgs nodejs
  # (same approach as openfic-git).
  pnpm' = stdenv.mkDerivation {
    pname = "pnpm-for-deepseek-harness";
    version = versionData.pnpmVersion;

    src = fetchurl {
      url = "https://registry.npmjs.org/pnpm/-/pnpm-${versionData.pnpmVersion}.tgz";
      hash = versionData.pnpmHash;
    };

    nativeBuildInputs = [
      nodejs_24
      makeWrapper
    ];

    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/pnpm"
      cp -r . "$out/lib/pnpm/"
      makeWrapper "${nodejs_24}/bin/node" "$out/bin/pnpm" \
        --add-flags "$out/lib/pnpm/bin/pnpm.cjs"
      runHook postInstall
    '';

    passthru = {
      # fetchPnpmDeps overrides pnpm-fixup-state-db with pnpm.nodejs-slim.
      nodejs-slim = nodejs-slim;
      nodejs = nodejs_24;
    };
  };

  # fetcherVersion 4: the SQLite store index is dumped to a deterministic SQL
  # text file (pnpm 11 stores are otherwise byte-non-reproducible).
  # manage-package-manager-versions=false keeps `packageManager` from
  # delegating to a downloaded pnpm; minimum-release-age=0 skips the
  # supply-chain metadata lookups that otherwise stall the fetch for minutes.
  pnpmDeps = fetchPnpmDeps {
    pname = "deepseek-harness-git";
    inherit src;
    pnpm = pnpm';
    fetcherVersion = 4;
    pnpmInstallFlags = [
      "--config.manage-package-manager-versions=false"
      "--config.minimum-release-age=0"
    ];
    hash = versionData.pnpmDepsHash;
  };

  # The dsh CLI (apps/cli) resolves its ~90 workspace dependencies through the
  # relative symlinks pnpm created in node_modules, and its `dsh.configTrees`
  # manifest reaches into ../../packages/preset/... — so the whole repository
  # layout (source + built lib outputs + node_modules) is shipped as-is and
  # the wrapper points straight at apps/cli/lib/bin.js.
in
stdenv.mkDerivation (finalAttrs: {
  inherit pname version src pnpmDeps;

  nativeBuildInputs = [
    nodejs_24
    pnpm'
    pnpmConfigHook
    makeWrapper
  ];

  env = {
    # Never let an interactive prompt block the sandbox (module purges).
    CI = "true";
    # Mirrors upstream release CI.
    DSH_TELEMETRY_DISABLED = "1";
    # build.ts wants `git rev-parse HEAD`; the tarball has no .git, so pass
    # the pinned rev explicitly (sliced to 7 chars upstream).
    DSH_CLIENT_COMMIT_HASH = rev;
    pnpm_config_manage_package_manager_versions = "false";
    pnpm_config_minimum_release_age = "0";
  };

  buildPhase = ''
    runHook preBuild

    # pnpmConfigHook already ran `pnpm install --offline` in postConfigure.
    # Full workspace build: tsc project build + tsdown bundles (lib) and the
    # vite frontend (web), exactly like the upstream release workflow.
    pnpm run build:official

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/${pname}"
    # cp -a preserves the pnpm symlink layout; every link inside is relative.
    cp -a -T . "$out/lib/${pname}"

    # pnpm leaves a few dangling links for optional platform binaries it did
    # not materialize (dev tooling like @oxlint-tsgolint and the aliased
    # @openai/codex platform alias; the published npm package ships neither).
    find "$out/lib/${pname}" -xtype l -delete

    # /bin/bash does not exist on NixOS (issue #8086)
    substituteInPlace \
      "$out/lib/${pname}/packages/terminal/terminal-bash/lib/index.js" \
      --replace-fail '"/bin/bash"' '"${lib.getExe bashInteractive}"'

    # dsh-sandbox-local probes `bwrap` from PATH for its preferred Linux
    # sandbox backend (chain: bwrap, then landlock); the landlock launcher's
    # optional platform package is not materialized by the offline pnpm
    # install, so bwrap is the only working backend here.
    makeWrapper "${nodejs_24}/bin/node" "$out/bin/dsh" \
      --argv0 dsh \
      --prefix PATH : ${lib.makeBinPath [ bubblewrap ]} \
      --add-flags "--expose-internals" \
      --add-flags "$out/lib/${pname}/apps/cli/lib/bin.js"

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
  ];
  versionCheckProgramArg = "--version";

  meta = {
    description = "Open-source agent harness and CLI developed by DeepSeek AI (built from git release tags)";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    changelog = "https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [
      # node-pty ships prebuilt platform bindings in prebuilds/
      binaryBytecode
      fromSource
    ];
    maintainers = [ ];
    mainProgram = "dsh";
    # Only x86_64-linux has been verified; widen after testing elsewhere
    # (node-pty ships prebuilds for linux/darwin x64+arm64, so the tree in
    # principle works on those too).
    platforms = [ "x86_64-linux" ];
  };
})
