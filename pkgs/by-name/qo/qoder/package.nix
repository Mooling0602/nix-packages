{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libappindicator-gtk3,
  libdrm,
  libglvnd,
  libnotify,
  libsecret,
  libuuid,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxscrnsaver,
  libxshmfence,
  libxtst,
  libxkbfile,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  wayland,
  xdg-utils,
}:

let
  version = "0.2.5";
in
stdenv.mkDerivation {
  pname = "qoder";
  inherit version;

  # Upstream split Qoder into separate products; this is the standalone Qoder
  # app, published from an electron-builder pipeline under `qoder-app/`. The
  # IDE lives in the separate `qoder-ide` package.
  src = fetchurl {
    url = "https://download.qoder.com/qoder-app/releases/${version}/Qoder-linux-amd64.deb";
    hash = "sha256-OMWqFRVNGFSI4Vwdre04409vkMtBP7iH4EAqkTVMpoA=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libappindicator-gtk3
    libdrm
    libglvnd
    libnotify
    libsecret
    libuuid
    libxkbcommon
    mesa
    nspr
    nss
    pango
    systemd
    wayland
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxscrnsaver
    libxshmfence
    libxtst
    libxkbfile
  ];

  unpackPhase = ''
    runHook preUnpack
    ar x "$src"
    tar -x --no-same-owner --no-same-permissions -f data.tar.xz
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"

    # Icons, desktop entry and doc.
    cp -r usr/* "$out"/

    # Upstream installs to /opt/Qoder; keep the same layout below $out.
    mkdir -p "$out/lib/qoder"
    cp -r opt/Qoder/* "$out/lib/qoder/"

    # Drop the musl builds of the native image/canvas modules: they are the
    # wrong libc for this platform and autoPatchelfHook cannot satisfy their
    # `libc.musl-x86_64.so.1` / `libc.so` dependencies. They cost ~46 MB.
    rm -rf \
      "$out/lib/qoder/resources/app.asar.unpacked/node_modules/@img/sharp-libvips-linuxmusl-x64" \
      "$out/lib/qoder/resources/app.asar.unpacked/node_modules/@img/sharp-linuxmusl-x64" \
      "$out/lib/qoder/resources/app.asar.unpacked/node_modules/@napi-rs/canvas-linux-x64-musl"

    # Keep only the Linux node-pty prebuilds; the Windows and macOS ones are
    # dead weight and carry foreign binaries. Linux loads build/Release/pty.node,
    # so an emptied prebuilds directory is harmless.
    node_pty_prebuilds="$out/lib/qoder/resources/app.asar.unpacked/node_modules/node-pty/prebuilds"
    if [ -d "$node_pty_prebuilds" ]; then
      find "$node_pty_prebuilds" -mindepth 1 -maxdepth 1 -type d ! -name 'linux-*' -exec rm -rf {} +
    fi

    # `chrome-sandbox` would have to be setuid root, which the Nix store cannot
    # provide, so the app is launched with --no-sandbox below.
    chmod 0755 "$out/lib/qoder/chrome-sandbox"

    mkdir -p "$out/bin"
    ln -s "$out/lib/qoder/qoder" "$out/bin/qoder"

    substituteInPlace "$out/share/applications/qoder.desktop" \
      --replace-fail "/opt/Qoder/qoder" "$out/bin/qoder"
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/lib/qoder/qoder" \
      --add-flags "--no-sandbox" \
      --add-flags "--password-store=gnome-libsecret" \
      --prefix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          mesa
          libglvnd
          libsecret
        ]
      }"
  '';

  meta = {
    description = "Agent workbench for human and AI software teams";
    longDescription = ''
      Qoder is a closed-source agent workbench for human and AI software teams.
      This package installs the standalone Qoder app; the separately
      distributed Qoder IDE is packaged as `qoder-ide`.

      The app is wrapped with `--no-sandbox` because its bundled Chromium
      sandbox helper would have to be setuid root, which the Nix store cannot
      provide.
    '';
    homepage = "https://qoder.com";
    changelog = "https://qoder.com/zh/changelog?type=app";
    license = lib.licenses.unfree;
    mainProgram = "qoder";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
