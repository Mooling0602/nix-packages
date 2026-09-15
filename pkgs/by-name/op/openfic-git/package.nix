{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  importPnpmLock,
  mitm-cache,
  writableTmpDirAsHomeHook,
  makeWrapper,
  makeDesktopItem,
  cacert,
  nodejs,
  electron_43,
}:

let
  # Update-managed pins live in hashes.json so update.sh never has to rewrite
  # Nix code; the vendored pnpm lockfiles next to this file are synced by the
  # same script and feed importPnpmLock below.
  pins = builtins.fromJSON (builtins.readFile ./hashes.json);

  # Tracks upstream main HEAD. The nix version only dates the commit —
  # desktop/package.json keeps its upstream version because the app's local
  # backend bootstrap requires a PyPI `openfic` release matching
  # app.getVersion().
  rev = pins.rev;
  version = pins.version;

  src = fetchFromGitHub {
    owner = "syrizelink";
    repo = "OpenFic";
    inherit rev;
    hash = pins.srcHash;
  };

  # Upstream maintains the lockfiles with pnpm 11.8 (desktop/package.json
  # pins it via `packageManager`). nixpkgs pnpm 11.22 changed offline and
  # supply-chain behaviour in ways that reject these lockfiles, so run the
  # exact pinned pnpm through nixpkgs nodejs.
  pnpm' = stdenv.mkDerivation {
    pname = "pnpm-for-openfic";
    version = pins.pnpmVersion;

    src = fetchurl {
      url = "https://registry.npmjs.org/pnpm/-/pnpm-${pins.pnpmVersion}.tgz";
      hash = pins.pnpmHash;
    };

    nativeBuildInputs = [
      nodejs
      makeWrapper
    ];

    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/pnpm"
      cp -r . "$out/lib/pnpm/"
      makeWrapper "${nodejs}/bin/node" "$out/bin/pnpm" \
        --add-flags "$out/lib/pnpm/bin/pnpm.cjs"
      runHook postInstall
    '';
  };

  # OpenFic has no pnpm workspace root: desktop/ and frontend/ are two
  # independent pnpm projects with separate lockfiles, both consumed by this
  # package. importPnpmLock turns each lockfile's integrity hashes into the
  # mitm-cache data for that project; both data sets are merged and fed to
  # mitm-cache.fetch once, so there is no aggregate dependency-store hash to
  # probe: the cache is reproducible by construction, and the build only
  # performs ordinary `pnpm install`s through the replay proxy.
  #
  # The vendored lockfiles must match the ones in src; update.sh syncs them
  # from the same revision, and `pnpm install --frozen-lockfile` fails loudly
  # if they ever drift.
  desktopDeps = lib.importJSON (importPnpmLock {
    pname = "openfic-desktop-deps";
    inherit version;
    lockFile = ./pnpm-lock.desktop.yaml;
  }).passthru.data;
  frontendDeps = lib.importJSON (importPnpmLock {
    pname = "openfic-frontend-deps";
    inherit version;
    lockFile = ./pnpm-lock.frontend.yaml;
  }).passthru.data;

  mitmCache = mitm-cache.fetch {
    name = "openfic-git-pnpm-mitm-cache";
    data =
      # Whenever both lockfiles pin the same registry URL they must agree on
      # the integrity hash; a mismatch would mean one of them is corrupt and
      # the merged cache would silently pick one of the two.
      assert lib.all
        (name: desktopDeps.${name} == frontendDeps.${name})
        (builtins.attrNames (builtins.intersectAttrs desktopDeps frontendDeps));
      desktopDeps // frontendDeps;
  };

  desktopItem = makeDesktopItem {
    name = "openfic-git";
    desktopName = "OpenFic (git)";
    genericName = "Novel Writing Tool";
    comment = "AI-native writing tool for fiction authors (built from git)";
    exec = "openfic-git %U";
    icon = "openfic-git";
    terminal = false;
    categories = [ "Utility" ];
    # The Electron app name is unchanged (openfic-desktop); the two OpenFic
    # packages are not meant to be installed side by side.
    startupWMClass = "openfic-desktop";
    keywords = [
      "novel"
      "writing"
      "fiction"
      "AI"
    ];
  };
in
stdenv.mkDerivation {
  pname = "openfic-git";
  inherit version src mitmCache;

  nativeBuildInputs = [
    pnpm'
    nodejs
    mitm-cache
    writableTmpDirAsHomeHook
    makeWrapper
  ];

  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
  # Never let an interactive prompt block the sandbox (module purges).
  env.CI = "true";
  # vite-plus (Rust) initializes an HTTP client at startup and panics when
  # the sandbox's dummy SSL_CERT_FILE yields no usable CA certificates.
  env.SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  # The desktop main process resolves the frontend build through the sibling
  # ../frontend/dist directory (protocol.ts getFrontendDistDir, non-packaged
  # mode), so frontend/ and desktop/ keep their repository layout at runtime.
  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    export pnpm_config_manage_package_manager_versions=false
    export pnpm_config_minimum_release_age=0
    export pnpm_config_package_import_method=clone-or-copy
    # pnpm 11 otherwise rejects these lockfiles during its supply-chain
    # checks; the mitm-cache setup hook exports a bare host:port in
    # $https_proxy, which pnpm only honours as an explicit config value.
    export pnpm_config_trust_lockfile=true
    export pnpm_config_pm_on_fail=ignore
    pnpm config set https-proxy "http://$https_proxy"

    pnpm --dir frontend install --ignore-scripts --frozen-lockfile
    pnpm --dir desktop install --ignore-scripts --frozen-lockfile
    # desktop's build script also builds the frontend (pnpm --dir ../frontend build).
    pnpm --dir desktop run build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    export HOME="$TMPDIR"
    export pnpm_config_manage_package_manager_versions=false
    export pnpm_config_minimum_release_age=0
    export pnpm_config_package_import_method=clone-or-copy

    mkdir -p "$out/share/openfic/frontend"
    # The main process reads the frontend through ../frontend/dist.
    cp -r frontend/dist "$out/share/openfic/frontend/dist"

    cp -r desktop "$out/share/openfic/desktop"

    # Ship only production dependencies (electron-updater, posthog-node,
    # tar-stream) in a plain hoisted layout; the dev toolchain stays behind.
    (
      cd "$out/share/openfic/desktop"
      rm -rf node_modules
      pnpm install --prod --ignore-scripts --frozen-lockfile \
        --node-linker=hoisted
    )

    install -Dm644 desktop/resources/icons/openfic.svg \
      "$out/share/icons/hicolor/scalable/apps/openfic-git.svg"
    mkdir -p "$out/share/applications"
    ln -s "${desktopItem}/share/applications/openfic-git.desktop" \
      "$out/share/applications/openfic-git.desktop"

    makeWrapper "${electron_43}/bin/electron" "$out/bin/openfic-git" \
      --set-default ELECTRON_SKIP_BINARY_DOWNLOAD 1 \
      --add-flags "$out/share/openfic/desktop"
    runHook postInstall
  '';

  # Runtime requirements (documented in README):
  #  - The local backend bootstrap downloads python-build-standalone and
  #    PyPI wheels at first launch; these are unpatched FHS binaries, so the
  #    host needs nix-ld enabled (programs.nix-ld.enable = true) to run them.
  #  - NIX_LD/NIX_LD_LIBRARY_PATH come from the session environment.
  meta = {
    description = "AI-native writing tool for fiction authors (built from git main)";
    homepage = "https://github.com/syrizelink/OpenFic";
    license = lib.licenses.asl20;
    mainProgram = "openfic-git";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
