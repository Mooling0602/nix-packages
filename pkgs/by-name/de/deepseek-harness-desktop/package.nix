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
# The desktop assembly, four Linux shell patches and the notification probe are
# new here; desktop.nix documents the on-disk layout, the five load-bearing
# details (each verified against the unmodified upstream application) and the
# patches (desktop-shell-patch.mjs).
{
  lib
, callPackage
, bubblewrap
, electron_44
, nodejs_24
, patchelf
, python312
, stdenvNoCC
, vips
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

  # pkgs.vips' default output is bin, so read the out output, which is where
  # libvips-cpp lives. It comes from whichever nixpkgs the consumer passes, and
  # sharpLibvips below is what makes that safe: note 5 in desktop.nix records why
  # the addon's own DT_NEEDED name does not pin a version.
  vipsLib = lib.getLib vips;

  # sharp's native addon crashes with the libvips it ships with (note 5 in
  # desktop.nix), so this stages a substitute under the exact name the addon asks
  # for. The name is read out of the addon rather than restated here, so a sharp
  # bump that moves to a new libvips series fails this build instead of
  # segfaulting the app at run time, and it is checked against the vips this
  # package links for the same reason.
  #
  # A symlink, not a copy: the addon only needs the name it asks for to be
  # findable on LD_LIBRARY_PATH, and the loader then maps the real library with
  # the substituted build's own RUNPATH intact.
  sharpLibvips = stdenvNoCC.mkDerivation {
    pname = "deepseek-harness-desktop-sharp-libvips";
    inherit version;

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    nativeBuildInputs = [ patchelf ];

    installPhase = ''
      runHook preInstall
      addon="$(ls ${outPath}/node_modules/.pnpm/@img+sharp-linux-x64@*/node_modules/@img/sharp-linux-x64/lib/sharp-linux-x64-*.node)"
      if [ "$(printf '%s\n' "$addon" | wc -l)" -ne 1 ]; then
        echo "desktop: expected exactly one sharp addon under ${outPath}/node_modules/.pnpm, got: $addon" >&2
        exit 1
      fi

      soname="$(patchelf --print-needed "$addon" | grep -E '^libvips-cpp[.]so[.]' || true)"
      if [ -z "$soname" ] || [ "$(printf '%s\n' "$soname" | wc -l)" -ne 1 ]; then
        echo "desktop: expected one libvips-cpp DT_NEEDED entry in $addon, got: $soname" >&2
        exit 1
      fi

      # libvips keeps ABI within a stable series and says so in its soname: the
      # ABI name is libvips-cpp.so.42, and the upstream patch version is the last
      # field of the versioned file (42.20.3 for the addon's 8.18.3), i.e. a
      # libtool revision change, which by definition carries no interface change.
      # Any release of the addon's own major.minor series is therefore a valid
      # substitute; another series is not, and fails here rather than at the
      # first raster operation.
      addon_series="''${soname#libvips-cpp.so.}"
      addon_series="''${addon_series%.*}"
      vips_series="${lib.versions.majorMinor vips.version}"
      if [ "$addon_series" != "$vips_series" ]; then
        echo "desktop: sharp's addon requires $soname (series $addon_series), but this package links vips ${vips.version} (series $vips_series)" >&2
        echo "desktop: the substitute must be the same upstream stable series as the libvips that prebuilt addon was linked against; move vips to the addon's series, then re-run this build and its sharp probe (note 5 in desktop.nix)" >&2
        exit 1
      fi

      # The real file, not the unversioned symlink, so the loader reports the
      # versioned name in its trace and the check below stays exact.
      set -- $(find ${vipsLib}/lib -maxdepth 1 -type f -name 'libvips-cpp.so.*')
      if [ "$#" -ne 1 ]; then
        echo "desktop: expected one libvips-cpp.so.* in ${vipsLib}/lib, found $#" >&2
        exit 1
      fi
      mkdir -p "$out/lib"
      ln -s "$1" "$out/lib/$soname"
      test -e "$out/lib/$soname"
      runHook postInstall
    '';
  };
in
callPackage ./desktop.nix {
  inherit lib stdenvNoCC version pnpmVersion;
  electron = electron_44;
  nodejs = nodejs_24;
  inherit bubblewrap nodeRuntimeVersion;
  # Build-time helpers, and the upstream sources they read. The two guards fail
  # the build when an upstream bump changes something these lists assume, which
  # is what makes an unattended version bump safe to trust. The shell-patch
  # script likewise fails the build when the bundle no longer matches the
  # anchors its Linux patches were written against, and the identity script
  # fails it when the desktop identity no longer matches the window Electron
  # will report.
  coverageScript = ./desktop-coverage.mjs;
  descriptorScript = ./desktop-runtime-json.mjs;
  shellPatchScript = ./desktop-shell-patch.mjs;
  identityScript = ./desktop-identity.mjs;
  hostManifest = "${outPath}/apps/desktop-host/package.json";
  protocolSource = "${outPath}/apps/desktop/src/host-protocol.ts";
  python = pythonEnv;
  pythonVersion = python312.version;
  inherit pythonPackages;
  appRoot = "${outPath}/apps/desktop";
  inherit dshRuntimeTree appModulesTree sharpLibvips;
  pnpmRoot = "${outPath}/node_modules/pnpm";
  skillOfficeAssets = "${outPath}/packages/skill/skill-office/assets";
}