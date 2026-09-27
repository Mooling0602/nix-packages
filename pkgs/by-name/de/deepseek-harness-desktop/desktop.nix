# Desktop assembly for deepseek-harness-desktop. Wiring lives in package.nix.
#
# Layout, relative to the output root:
#
#   deepseek-harness                            the Electron binary
#   resources/app/                              app.getAppPath()
#   resources/app/dsh/                          the bundled dsh runtime
#   resources/app/dsh/desktop-runtime.json      runtime descriptor
#   resources/runtime/office-skills/            boot-required skill assets
#   resources/runtime/bin/node                  standalone Node for skill-office
#   resources/runtime/pnpm/                     pnpm CLI
#   resources/runtime/primary-runtime/          interpreters + Python libraries
#   resources/icon.png                          window/taskbar icon
#
# Four details are load-bearing; each was verified experimentally against the
# unmodified upstream application.
#
#  1. The Electron binary must NOT be named 'electron'. Electron treats an
#     executable by that name as "the default app" and reports
#     app.isPackaged === false, which sends main.ts down its development branch.
#     Verified on identical trees: renamed -> isPackaged true, untouched -> false.
#
#  2. The bundled runtime lives at resources/app/dsh, not resources/dsh.
#     runtimeResources() (apps/desktop/src/main.ts) resolves the packaged path as
#     join(app.getAppPath(), 'dsh'), and upstream's electron-builder config packs
#     'dsh' *inside* the asar ({ from: dsh, to: 'dsh' }). This package ships no
#     asar, so app.getAppPath() is resources/app and the runtime sits beneath it.
#     With the runtime anywhere else the binary still starts, then dies later on
#     a missing desktop-runtime.json.
#
#  3. desktop-runtime.json is only partly validated at launch, which is why this
#     package checks it at build time instead. The reader the shipped shell runs
#     (readDesktopRuntime, inlined into lib/main.js) hard-fails unless both
#     @deepseek-ai/dsh and @deepseek-ai/dsh-desktop-host appear in sharedPackages
#     carrying exactly release.version, and unless release.nodeVersion and
#     release.pnpmVersion are semver strings. It does NOT compare
#     release.hostProtocolVersion, and it treats the 'files' inventory as
#     structural only: the byte-level integrity sweep and the protocol-generation
#     comparison both live in verifyDesktopRuntime, which upstream runs while
#     packaging and which never runs at launch. So an empty 'files' array is
#     legal (the store hash is a stronger guarantee), the protocol field is
#     informational at runtime, and a stale protocol or Node version would be
#     accepted silently. Both are therefore derived at build time (see 3a in the
#     install phase) rather than written down in package.nix.
#
#  4. Two environment variables are required at launch; the wrapper sets both.
#     CHROME_DEVEL_SANDBOX points Chromium at its setuid sandbox helper, exactly
#     as nixpkgs' own electron wrapper does. Without it the process dies on
#     SIGILL before printing anything, and the only alternative is --no-sandbox,
#     which disables the sandbox outright. LD_LIBRARY_PATH must carry libstdc++,
#     because N-API addons are dlopen()ed out of a per-user cache directory
#     (node-addon-native-custom-loader copies them out of the store first), so
#     they do not inherit the Electron binary's RPATH; without it the Host aborts
#     with "No usable native binding found for
#     node-addon-require-builtin-linux-x64-gnu".
{
  lib
, stdenvNoCC
, electron
, makeWrapper
, makeDesktopItem
, copyDesktopItems
, nodejs
, python
, glib
, gtk3
, gsettings-desktop-schemas
, stdenv

, version
, pnpmVersion
, pythonVersion
, pythonPackages
  # Version of the standalone Node that is linked into the primary runtime. It is
  # recorded in that payload's manifest and validated by parsePrimaryRuntime().
, nodeRuntimeVersion

  # Build-time helpers, and the upstream sources they read: the coverage guard
  # scripts, the Host manifest whose dependencies must all be linked, and the
  # source file declaring the lifecycle protocol generation.
, coverageScript
, descriptorScript
, hostManifest
, protocolSource

  # apps/desktop, the Electron shell (lib/, renderer/, resources/).
, appRoot
  # Already-assembled resources/app/{dsh,node_modules} trees.
, dshRuntimeTree
, appModulesTree
  # pnpm CLI payload and the Office skill assets.
, pnpmRoot
, skillOfficeAssets
}:

let
  # nixpkgs's Electron ships its payload under libexec/electron.
  electronDir = "${electron.unwrapped}/libexec/electron";

  # wrapGAppsHook3 only auto-wraps $out/bin and this binary is not there, so the
  # hook's two variables are spelled out by hand. They are kept as plain values
  # rather than a list of pre-joined "--prefix ..." strings: makeWrapper needs
  # each flag as its own argument, and passing a list through
  # lib.escapeShellArgs would quote a whole flag into a single argument, which it
  # rejects with "makeWrapper doesn't understand the arg --prefix ...".
  xdgDataDirs = lib.concatStringsSep ":" [
    "${gsettings-desktop-schemas}/share"
    "${gtk3}/share/gsettings-schemas/${gtk3.name}"
    "${glib}/share"
  ];
  gsettingsSchemasPath = "${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}";

  # libstdc++ must be on LD_LIBRARY_PATH (see note 4): the Node-API addon is
  # dlopen()ed out of a per-user cache directory, so it does not inherit the
  # Electron binary's RPATH.
  runtimeLibraryPath = lib.makeLibraryPath [ glib gtk3 stdenv.cc.cc.lib ];

  pythonMajorMinor = lib.versions.majorMinor pythonVersion;
  pythonSitePackages = "${python}/lib/python${pythonMajorMinor}/site-packages";

  # The template descriptorScript fills in. See note 3 for what the reader
  # checks. release.nodeVersion and release.hostProtocolVersion are omitted on
  # purpose: both describe the tree this build assembles, so the install phase
  # reads them out of that tree and passes them to the script.
  descriptorTemplate = builtins.toFile "desktop-runtime-template.json" (builtins.toJSON {
    schemaVersion = 1;
    release = {
      schemaVersion = 1;
      inherit version pnpmVersion;
    };
    platform = "linux";
    arch = if stdenvNoCC.hostPlatform.isAarch64 then "arm64" else "x64";
    sharedPackages = [
      { name = "@deepseek-ai/dsh"; inherit version; path = "node_modules/@deepseek-ai/dsh"; }
      { name = "@deepseek-ai/dsh-desktop-host"; inherit version; path = "node_modules/@deepseek-ai/dsh-desktop-host"; }
    ];
    files = [ ];
  });

  # parsePrimaryRuntime() validates this. workspaceDependencyPaths() then derives
  # the site-packages location from `python`, so that value must be the real one.
  runtimeManifest = builtins.toJSON {
    desktopVersion = version;
    platform = "linux";
    arch = if stdenvNoCC.hostPlatform.isAarch64 then "arm64" else "x64";
    python = pythonVersion;
    node = nodeRuntimeVersion;
    pnpm = pnpmVersion;
    inherit pythonPackages;
  };

  # nodeRuntimeVersion is the Node package's own version, which nixpkgs derives
  # from the release it packages. parsePrimaryRuntime() trusts this manifest when
  # the workspace-dependencies tool runs, so the claim is checked against the
  # binary that is actually linked; a mismatch fails the build, not the tool call.
  nodeVersionProbe = stdenvNoCC.mkDerivation {
    pname = "deepseek-harness-desktop-node-version";
    inherit version;
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      reported="$(${nodejs}/bin/node -p 'process.versions.node')"
      if [ "$reported" != "${nodeRuntimeVersion}" ]; then
        echo "desktop: runtime.json declares Node ${nodeRuntimeVersion} but ${nodejs}/bin/node reports $reported" >&2
        exit 1
      fi
      printf '%s' "$reported" > "$out"
      runHook postInstall
    '';
  };
in
stdenvNoCC.mkDerivation {
  pname = "deepseek-harness-desktop";
  inherit version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  nativeBuildInputs = [ makeWrapper copyDesktopItems ];

  desktopItems = [
    (makeDesktopItem {
      name = "deepseek-harness";
      desktopName = "DeepSeek Harness";
      comment = "Open-source agent harness developed by DeepSeek AI";
      exec = "deepseek-harness %u";
      icon = "deepseek-harness";
      categories = [ "Development" ];
      startupWMClass = "DeepSeek Harness";
      mimeTypes = [ "x-scheme-handler/dsh" ];
    })
  ];

  installPhase = ''
    runHook preInstall
    # 1. The Electron distribution. A real copy, not a symlink: resourcesPath is
    #    derived from the realpath of the executable, so a symlinked binary would
    #    resolve back into the store and resources/app would never be found.
    mkdir -p "$out"
    cp -a ${electronDir}/. "$out/"
    chmod -R u+w "$out"
    mv "$out/electron" "$out/deepseek-harness"        # see note 1
    chmod +x "$out/deepseek-harness"

    # The bundled Electron reports the Node version this release ships. It is read
    # here, before the application tree exists, so the probe sees the bare Electron
    # distribution: with resources/app present the binary would find an application
    # to run. ELECTRON_RUN_AS_NODE makes it behave as plain Node, which is how
    # upstream's prepare-runtime.ts reads the same value.
    if ! node_version="$(ELECTRON_RUN_AS_NODE=1 "$out/deepseek-harness" -p 'process.versions.node' 2>&1)"; then
      echo "desktop: the bundled Electron failed to report process.versions.node: $node_version" >&2
      exit 1
    fi
    if [ -z "$node_version" ]; then
      echo "desktop: the bundled Electron reported an empty process.versions.node" >&2
      exit 1
    fi

    resources="$out/resources"
    rm -f "$resources/default_app.asar"

    # 2. The Electron shell at app.getAppPath(), plus its production modules.
    app="$resources/app"
    mkdir -p "$app/lib"
    cp -a ${appRoot}/lib/. "$app/lib/"
    cp -a ${appRoot}/renderer "$app/renderer"
    cp -a ${appRoot}/resources "$app/resources"
    cp ${appRoot}/package.json "$app/package.json"
    chmod -R u+w "$app"
    find "$app/lib" -name '*.tsbuildinfo' -delete
    cp -a ${appModulesTree} "$app/node_modules"

    # 3. The bundled dsh runtime, inside the app directory (see note 2), plus the
    #    descriptor readDesktopRuntime() validates before the Host is started.
    #    cp -a preserves the store's read-only modes, so the tree is made writable
    #    before the descriptor is added to it.
    cp -a ${dshRuntimeTree} "$app/dsh"
    chmod -R u+w "$app/dsh"

    # 3a. The two release facts that describe this tree are read out of it rather
    #     than restated in package.nix, so an upstream bump cannot leave them
    #     stale. The shell type-checks both without comparing either, so a stale
    #     copy would be accepted silently at launch.
    #
    #     nodeVersion: what the bundled Electron reports as process.versions.node.
    #     ELECTRON_RUN_AS_NODE makes the renamed binary run as plain Node, which is
    #     how upstream's prepare-runtime.ts obtains it too.
    #
    #     hostProtocolVersion: the lifecycle generation upstream compiles into its
    #     release metadata. Read from apps/desktop/src/host-protocol.ts, which is
    #     the declaration of record. electron-builder never ships lib/types -- its
    #     `files` list is lib/main.js, the five preloads, lib/welcome, renderer and
    #     package.json -- and the shipped main.js inlines readDesktopRuntime without
    #     comparing this field. The check that used to be here read
    #     lib/types/host-protocol.js, a file that is copied but never loaded.
    host_protocol_version="$(sed -n 's/.*DESKTOP_HOST_PROTOCOL_VERSION = \([0-9][0-9]*\).*/\1/p' ${protocolSource} | head -n 1)"
    if [ -z "$host_protocol_version" ]; then
      echo "desktop: no DESKTOP_HOST_PROTOCOL_VERSION in ${protocolSource}" >&2
      exit 1
    fi
    # Verify the Node the primary runtime links and declares (see nodeVersionProbe).
    # The value is unused below beyond this check, but reading it here makes the
    # probe a build dependency of the output rather than a detached derivation.
    # `cat`, not `read`: the probe writes no trailing newline, and `read` returns
    # non-zero at a premature EOF, which under `set -e` would abort silently.
    node_runtime_version="$(cat ${nodeVersionProbe})"
    if [ -z "$node_runtime_version" ]; then
      echo "desktop: the primary-runtime Node version probe produced nothing" >&2
      exit 1
    fi
    cp ${descriptorTemplate} "$app/dsh/desktop-runtime.json"
    chmod u+w "$app/dsh/desktop-runtime.json"
    ${nodejs}/bin/node ${descriptorScript} \
      "$app/dsh/desktop-runtime.json" "$app/dsh/desktop-runtime.json" \
      "$host_protocol_version" "$node_version"

    # 3b. The descriptor still has to satisfy the reader that actually ships.
    #     lib/main.js is ESM loaded by Electron, so it cannot be imported here;
    #     instead the invariants whose failure would surface at launch are checked
    #     directly: both shared packages must carry release.version at a path that
    #     exists, and every release field the reader requires must be present.
    ${nodejs}/bin/node -e '
      const { readFileSync, existsSync } = require("node:fs");
      const { join } = require("node:path");
      // The descriptor sits at the runtime root, and every path it records is
      // relative to that same root ($app/dsh), not to the application directory.
      const root = process.argv[1];
      const d = JSON.parse(readFileSync(join(root, "desktop-runtime.json"), "utf8"));
      for (const name of ["@deepseek-ai/dsh", "@deepseek-ai/dsh-desktop-host"]) {
        const e = d.sharedPackages.find(p => p.name === name);
        if (!e || e.version !== d.release.version) { console.error("desktop: descriptor has no " + name + " at " + d.release.version); process.exit(1); }
        if (!existsSync(join(root, e.path, "package.json"))) { console.error("desktop: descriptor path " + e.path + " is missing"); process.exit(1); }
      }
      for (const f of ["nodeVersion", "pnpmVersion", "hostProtocolVersion"]) {
        if (d.release[f] === undefined) { console.error("desktop: descriptor lacks release." + f); process.exit(1); }
      }
    ' "$app/dsh"

    # 3c. Both explicit module lists in package.nix are checked against upstream
    #     rather than trusted. A package upstream adds to either manifest and this
    #     file does not list fails at launch with ERR_MODULE_NOT_FOUND today; here
    #     it fails the build and names the package.
    ${nodejs}/bin/node ${coverageScript} app "$app"
    ${nodejs}/bin/node ${coverageScript} host "$app/dsh" ${hostManifest}

    # 4. Loosely-packed resources read through process.resourcesPath.
    cp ${appRoot}/resources/icon.png "$resources/icon.png"

    mkdir -p "$resources/runtime/bin"
    # skill-office refuses to load in a packaged app without a standalone Node.
    cp ${appRoot}/scripts/node-bin/node "$resources/runtime/bin/node"
    chmod +x "$resources/runtime/bin/node"
    cp -a ${pnpmRoot}/. "$resources/runtime/pnpm/"
    cp -a ${skillOfficeAssets} "$resources/runtime/office-skills"

    # primary-runtime: the interpreters and libraries behind the
    # load_workspace_dependencies tool. validatePayloadEntries() requires the
    # python file, the node file and the site-packages directory to exist.
    pr="$resources/runtime/primary-runtime"
    mkdir -p "$pr/dependencies/node/bin" "$pr/dependencies/node/node_modules"
    mkdir -p "$pr/dependencies/python/bin"
    mkdir -p "$pr/dependencies/python/lib/python${pythonMajorMinor}"
    ln -s ${nodejs}/bin/node "$pr/dependencies/node/bin/node"
    ln -s ${python}/bin/python3 "$pr/dependencies/python/bin/python3"
    cp -a ${pythonSitePackages} \
      "$pr/dependencies/python/lib/python${pythonMajorMinor}/site-packages"
    cp ${builtins.toFile "runtime.json" runtimeManifest} "$pr/runtime.json"

    # 5. Desktop-entry icon.
    install -Dm644 ${appRoot}/resources/icon.png \
      "$out/share/icons/hicolor/512x512/apps/deepseek-harness.png"

    # 6. The launcher. See note 4.
    makeWrapper "$out/deepseek-harness" "$out/bin/deepseek-harness" \
      --set CHROME_DEVEL_SANDBOX "$out/chrome-sandbox" \
      --prefix LD_LIBRARY_PATH : "${runtimeLibraryPath}" \
      --prefix PATH : "${nodejs}/bin" \
      --prefix XDG_DATA_DIRS : "${xdgDataDirs}" \
      --prefix GSETTINGS_SCHEMAS_PATH : "${gsettingsSchemasPath}"

    runHook postInstall
  '';

  meta = {
    description = "Electron desktop shell for DeepSeek Harness";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "deepseek-harness";
  };
}