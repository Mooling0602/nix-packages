{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, makeWrapper
, alsa-lib
, at-spi2-atk
, at-spi2-core
, cairo
, dbus
, expat
, gdk-pixbuf
, glib
, gtk3
, libdrm
, libglvnd
, libnotify
, libsecret
, libuuid
, libx11
, libxcb
, libxcomposite
, libxcursor
, libxdamage
, libxext
, libxfixes
, libxi
, libxkbcommon
, libxrandr
, libxrender
, libxscrnsaver
, libxshmfence
, libxtst
, libxkbfile
, mesa
, nspr
, nss
, pango
, systemd
, wayland
}:

let
  version = "1.2.0";
in
stdenv.mkDerivation {
  pname = "qoder";
  inherit version;

  src = fetchurl {
    url = "https://download.qoder.com/release/${version}/qoder_amd64.deb";
    hash = "sha256-Ls7C2g7+y6A1UISmtJbkC6KScVRhTv481558TBY/MmA=";
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
    if [ -f "$out/share/qoder/qoder" ]; then
      ln -s "$out/share/qoder/qoder" "$out/bin/qoder"
    else
      echo "Error: main executable not found at $out/share/qoder/qoder" >&2
      exit 1
    fi
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/share/qoder/qoder" \
      --add-flags "--no-sandbox" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ mesa libglvnd libsecret ]}"
  '';

  meta = {
    description = "Agentic AI coding platform for real software development";
    homepage = "https://qoder.com";
    license = lib.licenses.unfree;
    mainProgram = "qoder";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
