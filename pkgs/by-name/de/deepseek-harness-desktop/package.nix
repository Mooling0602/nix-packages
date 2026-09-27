# Standalone Nix package for the DeepSeek Harness desktop application.
#
# Why this is a separate package and not a second output of
# deepseek-harness-git: Nix builds every output of a derivation in one builder
# invocation. Measured on a probe derivation with outputs = [ "out" "desktop" ]
# whose desktop output referenced a unique throwaway dependency, `nix build
# ...out` printed "these 2 derivations will be built" and built that
# desktop-only dependency as well. A second output would therefore make every
# plain `nix build .#deepseek-harness-git` fetch a 360 MiB Electron and run the
# desktop installPhase. Keeping the two separate means CLI/Web users never touch
# Electron. (The two outputs' *runtime closures* are in fact independent; it is
# the build cost, not closure size, that forces the split.)
#
# Only the desktop assembly is new here; desktop.nix documents the on-disk
# layout and the four load-bearing details, each verified against the unmodified
# upstream application.
{
  lib
, callPackage
, electron_44
, nodejs_24
, python312
, stdenvNoCC
}:

let
  # Reuse the sibling source package. Identical call arguments memoise to the
  # same derivation, so this shares deepseek-harness-git's single fetchFromGitHub
  # and single pnpm install rather than duplicating either.
  dsh = callPackage ../deepseek-harness-git/package.nix { };

  # Read from the source package's own pin file: importing a manifest out of
  # dsh's store path would be an import-from-derivation and would also require
  # that package to be built just to evaluate this one.
  versionData = lib.importJSON ../deepseek-harness-git/hashes.json;
  inherit (versionData) version pnpmVersion;

  # deepseek-harness-git installs the repository tree under $out/lib/<pname>,
  # not at the store root (see its installPhase).
  outPath = "${dsh}/lib/deepseek-harness-git";

  # release.nodeVersion and release.hostProtocolVersion are deliberately not
  # written down here. Both describe the tree the build assembles -- what the
  # bundled Electron reports, and the protocol generation in upstream's
  # apps/desktop/src/host-protocol.ts -- so desktop.nix reads them out of that
  # tree. A literal would go stale on an upstream or nixpkgs bump, and the
  # shipped shell accepts both fields without comparing either, so the drift
  # would not show up as a launch failure.
  #
  # This one is different: it is the standalone Node the primary runtime links,
  # and parsePrimaryRuntime() records it as the payload's version. Taking it from
  # the package being linked keeps the claim true when nixpkgs bumps Node.
  nodeRuntimeVersion = nodejs_24.version;

  pythonEnv = python312.withPackages (ps: with ps; [
    numpy
    pandas
    python-dateutil
    six
    tzdata
    python-docx
    python-pptx
    openpyxl
    pillow
    lxml
    xlsxwriter
    typing-extensions
    et-xmlfile
  ]);

  # Names and versions must satisfy isDistributionMap() in
  # tool-workspace-dependencies: names ^[A-Za-z0-9][A-Za-z0-9._-]*$ and versions
  # ^[0-9][\w.!+-]*$. Read from the very packages linked below, so the manifest
  # cannot drift from the payload.
  pythonPackages = {
    numpy = python312.pkgs.numpy.version;
    pandas = python312.pkgs.pandas.version;
    python-dateutil = python312.pkgs.python-dateutil.version;
    six = python312.pkgs.six.version;
    tzdata = python312.pkgs.tzdata.version;
    python-docx = python312.pkgs.python-docx.version;
    python-pptx = python312.pkgs.python-pptx.version;
    openpyxl = python312.pkgs.openpyxl.version;
    Pillow = python312.pkgs.pillow.version;
    lxml = python312.pkgs.lxml.version;
    XlsxWriter = python312.pkgs.xlsxwriter.version;
    typing_extensions = python312.pkgs.typing-extensions.version;
    et_xmlfile = python312.pkgs.et-xmlfile.version;
  };

  # The shell's production dependencies, listed explicitly rather than globbed
  # so build-only tooling (typescript, vite, electron-builder, app-builder-lib,
  # @electron, @types, pnpm) stays out of the runtime closure. The npm `electron`
  # package is deliberately absent: main.js resolves 'electron' from the runtime.
  appModules = [
    "semver"
    "ws"
    "electron-updater"
    "koffi"
    "sharp"
    "js-yaml"
    "extract-zip"
    "react"
    "react-dom"
    "cos-nodejs-sdk-v5"
    "@deepseek-ai/cordis"
    "@deepseek-ai/dsh-api-gateway"
    "@deepseek-ai/dsh-app-boot"
    "@deepseek-ai/dsh-atomic-write"
    "@deepseek-ai/dsh-client-shortcuts"
    "@deepseek-ai/dsh-client-ui-primitives"
    "@deepseek-ai/dsh-client-ui-settings-general"
    "@deepseek-ai/dsh-client-ui-sidebar-browser"
    "@deepseek-ai/dsh-client-ui-theme"
    "@deepseek-ai/dsh-deepseek-account"
    "@deepseek-ai/dsh-home-paths"
    "@deepseek-ai/node-addon-system"
  ];

  # Host direct dependencies, resolved by bare name at startup. Linked rather
  # than copied: pnpm's layout is a web of relative symlinks, so copying only
  # this subtree would leave them dangling.
  hostDependencies = [
    "cordis"
    "dsh-agent"
    "dsh-app-boot"
    "dsh-client-connection"
    "dsh-deepseek-account"
    "dsh-home-paths"
    "dsh-host-webserver"
    "dsh-jobs"
    "dsh-schedule"
    "dsh-skill-office"
    "dsh-tool-workspace-dependencies"
    "dsh-workspace"
    "libreoffice-kit"
  ];

  # resources/app/dsh: the bundled runtime. Links point at the shared store tree;
  # each target's own relative links still resolve, because they are followed
  # from the target's real location.
  dshRuntimeTree = stdenvNoCC.mkDerivation {
    pname = "deepseek-harness-desktop-runtime";
    inherit version;
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/node_modules/@deepseek-ai"
      ln -s ${outPath}/apps/cli          "$out/node_modules/@deepseek-ai/dsh"
      ln -s ${outPath}/apps/web          "$out/node_modules/@deepseek-ai/dsh-web-frontend"
      ln -s ${outPath}/apps/desktop-host "$out/node_modules/@deepseek-ai/dsh-desktop-host"
      for name in ${lib.concatStringsSep " " hostDependencies}; do
        ln -s "${outPath}/apps/desktop-host/node_modules/@deepseek-ai/$name" \
          "$out/node_modules/@deepseek-ai/$name"
      done
      cat > "$out/package.json" <<'JSON'
      {
        "name": "@deepseek-ai/dsh-desktop-runtime",
        "private": true,
        "version": "${version}",
        "type": "module"
      }
      JSON
      runHook postInstall
    '';
  };

  # resources/app/node_modules, staged as a tree so desktop.nix can copy it.
  appModulesTree = stdenvNoCC.mkDerivation {
    pname = "deepseek-harness-desktop-app-modules";
    inherit version;
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      for name in ${lib.concatStringsSep " " appModules}; do
        mkdir -p "$out/$(dirname "$name")"
        ln -s "${outPath}/apps/desktop/node_modules/$name" "$out/$name"
      done
      runHook postInstall
    '';
  };
in
callPackage ./desktop.nix {
  inherit lib stdenvNoCC version pnpmVersion;
  electron = electron_44;
  nodejs = nodejs_24;
  inherit nodeRuntimeVersion;
  # Build-time helpers, and the upstream sources they read. The two guards fail
  # the build when an upstream bump changes something these lists assume, which
  # is what makes an unattended version bump safe to trust.
  coverageScript = ./desktop-coverage.mjs;
  descriptorScript = ./desktop-runtime-json.mjs;
  hostManifest = "${outPath}/apps/desktop-host/package.json";
  protocolSource = "${outPath}/apps/desktop/src/host-protocol.ts";
  python = pythonEnv;
  pythonVersion = python312.version;
  inherit pythonPackages;
  appRoot = "${outPath}/apps/desktop";
  inherit dshRuntimeTree appModulesTree;
  pnpmRoot = "${outPath}/node_modules/pnpm";
  skillOfficeAssets = "${outPath}/packages/skill/skill-office/assets";
}