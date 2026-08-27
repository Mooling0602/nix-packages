{
  lib,
  stdenv,
  fetchurl,
  buildFHSEnv,
  makeDesktopItem,
}:

let
  version = "0.10.2";

  # Upstream is an electron-builder distribution. The Python backend is not
  # shipped in the tarball: the desktop app downloads a python-build-standalone
  # CPython from GitHub and installs the `openfic` backend from PyPI into a
  # venv at first launch. Those runtime-downloaded ELF binaries hard-code the
  # FHS interpreter path (/lib64/ld-linux-x86-64.so.2), so the app is wrapped
  # in a bubblewrap FHS environment instead of relying on autoPatchelf.
  dist = stdenv.mkDerivation {
    pname = "openfic-dist";
    inherit version;

    src = fetchurl {
      url = "https://github.com/syrizelink/OpenFic/releases/download/v${version}/OpenFic-${version}-linux-x86_64.tar.gz";
      hash = "sha256-KstocPWQYt9g7b9cXtpNm5TuCXpQRZ3qdf73o6V9lzM=";
    };

    sourceRoot = "OpenFic-${version}-linux-x64";

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    dontPatchELF = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/opt/openfic"
      cp -r . "$out/opt/openfic/"
      runHook postInstall
    '';
  };

  desktopItem = makeDesktopItem {
    name = "openfic";
    desktopName = "OpenFic";
    genericName = "Novel Writing Tool";
    comment = "AI-native writing tool for fiction authors";
    exec = "openfic %U";
    icon = "openfic";
    terminal = false;
    categories = [ "Utility" ];
    startupWMClass = "openfic-desktop";
    keywords = [
      "novel"
      "writing"
      "fiction"
      "AI"
    ];
  };
in
buildFHSEnv {
  pname = "openfic";
  inherit version;

  targetPkgs =
    pkgs:
    with pkgs;
    [
      # FHS interpreter and runtime libs for the prebuilt/wheel binaries the
      # app downloads at runtime (CPython, onnxruntime, lancedb, ...).
      glibc
      libgcc
      stdenv.cc.cc.lib
      openssl
      zlib

      # Electron / Chromium GUI stack.
      alsa-lib
      at-spi2-atk
      at-spi2-core
      cairo
      cups
      dbus
      expat
      fontconfig
      glib
      gtk3
      libdrm
      libgbm
      libglvnd
      libnotify
      libsecret
      libuuid
      libx11
      libxcb
      libxcomposite
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxi
      libxkbcommon
      libxkbfile
      libxrandr
      libxrender
      libxscrnsaver
      libxshmfence
      libxtst
      mesa
      nspr
      nss
      pango
      systemdLibs
      wayland
    ];

  extraBwrapArgs = [
    # Let the system fontconfig configuration reach the sandbox.
    "--ro-bind-try /etc/xdg/ /etc/xdg/"
  ];

  # chrome-sandbox cannot be setuid inside the store or the bwrap sandbox.
  runScript = "${dist}/opt/openfic/openfic-desktop --no-sandbox";

  dieWithParent = false;

  extraInstallCommands = ''
    mkdir -p "$out/share/applications"
    ln -s "${desktopItem}/share/applications/openfic.desktop" "$out/share/applications/openfic.desktop"
    install -Dm644 "${dist}/opt/openfic/resources/frontend-dist/openfic.svg" \
      "$out/share/icons/hicolor/scalable/apps/openfic.svg"
  '';

  meta = {
    description = "AI-native, cross-platform writing tool for fiction authors";
    homepage = "https://github.com/syrizelink/OpenFic";
    license = lib.licenses.asl20;
    mainProgram = "openfic";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
