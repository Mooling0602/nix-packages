{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  fetchPnpmDeps,
  makeWrapper,
  makeDesktopItem,
  cacert,
  nodejs,
  nodejs-slim,
  sqlite,
  zstd,
  electron_43,
}:

let
  # Tracks upstream main HEAD; see update.sh. The nix version only dates the
  # commit — desktop/package.json keeps its upstream version (currently
  # 0.10.1) because the app's local backend bootstrap requires a PyPI
  # `openfic` release matching app.getVersion().
  rev = "b5c2e0bbc38e08b7d525997a47797165d40648e4";
  version = "unstable-2026-08-30";

  src = fetchFromGitHub {
    owner = "syrizelink";
    repo = "OpenFic";
    inherit rev;
    hash = "sha256-6AxIG3l/208uKn1VSX3vaOslT5Amp1jQtr4T3Lr9uuE=";
  };

  # Upstream maintains the lockfiles with pnpm 11.8 (desktop/package.json
  # pins it via `packageManager`). nixpkgs pnpm 11.22 changed offline and
  # supply-chain behaviour in ways that reject these lockfiles, so run the
  # exact pinned pnpm through nixpkgs nodejs.
  pnpm' = stdenv.mkDerivation {
    pname = "pnpm-for-openfic";
    version = "11.8.0";

    src = fetchurl {
      url = "https://registry.npmjs.org/pnpm/-/pnpm-11.8.0.tgz";
      hash = "sha256-HpY6XEylFoVQugP8TujYc6dysHK3/OY7SP/yfXIOLpg=";
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

    passthru = {
      # fetchPnpmDeps overrides pnpm-fixup-state-db with pnpm.nodejs-slim.
      nodejs-slim = nodejs-slim;
      nodejs = nodejs;
    };
  };

  # OpenFic has no pnpm workspace root: desktop/ and frontend/ are two
  # independent pnpm projects with separate lockfiles, both consumed by this
  # package. fetchPnpmDeps insists on a lockfile at the source root, so
  # preInstall re-roots the checks onto desktop/, prePnpmInstall populates
  # the frontend packages and leaves the working directory on desktop/ for
  # the main install — both installs share one store, which nixpkgs then
  # normalizes into a reproducible tarball (fetcherVersion 4: fixup-state-db,
  # SQLite index dumped as SQL text, sorted JSON, stable permissions).
  #
  # manage-package-manager-versions=false keeps `packageManager` from
  # delegating to a downloaded pnpm; minimum-release-age=0 disables
  # supply-chain metadata lookups that fail inside the build sandbox.
  pnpmDeps = fetchPnpmDeps {
    pname = "openfic-git";
    inherit version src;
    pnpm = pnpm';
    # fetcherVersion 4: the SQLite store index is dumped to a deterministic
    # SQL text file (pnpm 11 stores are otherwise byte-non-reproducible).
    fetcherVersion = 4;

    preInstall = ''
      cp desktop/pnpm-lock.yaml desktop/pnpm-workspace.yaml .
    '';

    prePnpmInstall = ''
      (
        cd frontend
        pnpm install --force --ignore-scripts --frozen-lockfile \
          --config.manage-package-manager-versions=false \
          --config.minimum-release-age=0
      )
      cd desktop
    '';

    pnpmInstallFlags = [
      "--config.manage-package-manager-versions=false"
      "--config.minimum-release-age=0"
    ];

    hash = "sha256-0hWjOg7e7MJ66cSDhta6Lm1qWhV7nya8I03ogzkqZyo=";
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
  inherit version src;

  nativeBuildInputs = [
    pnpm'
    nodejs
    sqlite
    zstd
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

    # Unpack the reproducible dependency store and work on a writable copy:
    # offline installs register the project inside the store (SQLite index).
    store="$TMPDIR/pnpm-store"
    mkdir -p "$store"
    tar --zstd -xf "${pnpmDeps}/pnpm-store.tar.zst" -C "$store"
    chmod -R +w "$store"
    # fetcherVersion 4 ships the store index as deterministic SQL text
    # (mirroring pnpmConfigHook); reconstruct the binary database.
    if [ -f "$store/v11/index.db.sql" ]; then
      sqlite3 "$store/v11/index.db" < "$store/v11/index.db.sql"
      rm "$store/v11/index.db.sql"
    fi

    pnpm --dir frontend install --offline --ignore-scripts --frozen-lockfile --store-dir "$store"
    pnpm --dir desktop install --offline --ignore-scripts --frozen-lockfile --store-dir "$store"
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
    store="$TMPDIR/pnpm-store"

    mkdir -p "$out/share/openfic/frontend"
    # The main process reads the frontend through ../frontend/dist.
    cp -r frontend/dist "$out/share/openfic/frontend/dist"

    cp -r desktop "$out/share/openfic/desktop"

    # Ship only production dependencies (electron-updater, posthog-node,
    # tar-stream) in a plain hoisted layout; the dev toolchain stays behind.
    (
      cd "$out/share/openfic/desktop"
      rm -rf node_modules
      pnpm install --prod --offline --ignore-scripts --frozen-lockfile \
        --node-linker=hoisted --store-dir "$store"
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
