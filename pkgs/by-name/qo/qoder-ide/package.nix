{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  at-spi2-atk,
  bubblewrap,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
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
}:

let
  version = "1.32.0";
in
stdenv.mkDerivation {
  pname = "qoder-ide";
  inherit version;

  # Upstream renamed the IDE product from `qoder` to `qoder-ide` in 1.25.1 and
  # moved the download path with it; the pre-rename `qoder_amd64.deb` URL is
  # frozen at 1.24.2.
  src = fetchurl {
    url = "https://download.qoder.com/release/${version}/qoder-ide_amd64.deb";
    hash = "sha256-+jCOu2X4K36uOcjG1Y32zk7jyewE8ngRXfbkucC4v40=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    bubblewrap
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
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
    cp -r usr/* "$out"/
    mkdir -p "$out/bin"
    if [ -f "$out/share/qoder-ide/qoder-ide" ]; then
      ln -s "$out/share/qoder-ide/qoder-ide" "$out/bin/qoder-ide"
    else
      echo "Error: main executable not found at $out/share/qoder-ide/qoder-ide" >&2
      exit 1
    fi
    for f in "$out/share/applications/"*.desktop; do
      substituteInPlace "$f" --replace-fail "/usr/share/qoder-ide/qoder-ide" "$out/bin/qoder-ide"
    done
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/share/qoder-ide/qoder-ide" \
      --add-flags "--no-sandbox" \
      --add-flags "--password-store=gnome-libsecret" \
      --prefix PATH : "${bubblewrap}/bin" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          mesa
          libglvnd
          libsecret
        ]
      }"
  '';

  meta = {
    description = "Agentic AI coding platform for real software development";
    longDescription = ''
      Qoder IDE is the desktop IDE of the Qoder agentic coding platform. This
      package installs the IDE itself; the separately distributed Qoder app and
      the standalone `qoder` CLI are not included. The IDE's own CLI bridge
      lives at `$out/share/qoder-ide/bin/qoder`.
    '';
    homepage = "https://qoder.com";
    changelog = "https://qoder.com/zh/changelog?type=ide";
    license = lib.licenses.unfree;
    mainProgram = "qoder-ide";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
