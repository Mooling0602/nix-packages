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
  version = "0.15.0";
in
stdenv.mkDerivation {
  pname = "clawd-on-desk";
  inherit version;

  src = fetchurl {
    url = "https://github.com/rullerzhou-afk/clawd-on-desk/releases/download/v${version}/Clawd-on-Desk-${version}-amd64.deb";
    hash = "sha256-s1W/nnn/N9Hr3jHfq+AZ18QmE5iVgjN9Mnrf6YcLy+s=";
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

    # Copy usr contents (icons, applications, doc)
    cp -r usr/* "$out"/

    # Copy the main app from opt, using a path without spaces
    mkdir -p "$out/lib/clawd-on-desk"
    cp -r "opt/Clawd on Desk/"* "$out/lib/clawd-on-desk/"

    # Remove foreign koffi native modules to avoid autoPatchelf errors
    for f in "$out/lib/clawd-on-desk/resources/app.asar.unpacked/node_modules/koffi/build/koffi"/*/koffi.node; do
      case "$(dirname "$f")" in */linux_x64) ;; *) rm -f "$f" ;; esac
    done

    # Symlink the main executable
    mkdir -p "$out/bin"
    ln -s "$out/lib/clawd-on-desk/clawd-on-desk" "$out/bin/clawd-on-desk"

    # Fix desktop file Exec path
    substituteInPlace "$out/share/applications/clawd-on-desk.desktop" \
      --replace-fail 'Exec="/opt/Clawd on Desk/clawd-on-desk"' "Exec=$out/bin/clawd-on-desk"
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/clawd-on-desk" \
      --add-flags "--no-sandbox" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          mesa
          libglvnd
          libsecret
        ]
      }"
  '';

  meta = {
    description = "Desktop companion pet that reacts to AI coding assistant sessions in real time";
    homepage = "https://github.com/rullerzhou-afk/clawd-on-desk";
    license = lib.licenses.agpl3Only;
    mainProgram = "clawd-on-desk";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
