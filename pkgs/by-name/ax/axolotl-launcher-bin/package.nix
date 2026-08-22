{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  webkitgtk_4_1,
  gtk3,
  libsoup_3,
  glib,
  glib-networking,
  gdk-pixbuf,
  cairo,
  dbus,
  libayatana-appindicator,
  pango,
  harfbuzz,
  fontconfig,
  freetype,
  libGL,
  gst_all_1,
}:

let
  gstreamer = gst_all_1.gstreamer;
  gst-plugins-base = gst_all_1.gst-plugins-base;
  gst-plugins-good = gst_all_1.gst-plugins-good;
  gst-plugins-bad = gst_all_1.gst-plugins-bad;

  # GStreamer plugin search path. WebKit instantiates media elements via
  # GStreamer; without this, it fails with "GStreamer element appsink not
  # found" because the plugins are not on the runtime plugin path.
  gstPluginsPath = lib.makeSearchPath "lib/gstreamer-1.0" [
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
  ];
in

let
  pname = "axolotl-launcher-bin";
  version = "1.8.10";

  src = fetchurl {
    url = "https://github.com/Mystic-Stars/Axolotl/releases/download/v${version}/Axolotl.Launcher_${version}_amd64.deb";
    hash = "sha256-YH2CQc1vz7MErMe3ejiLYDniZyeNoSmHbiV5L2Fbid8=";
  };

in
stdenv.mkDerivation {
  inherit pname version;

  src = src;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    webkitgtk_4_1
    gtk3
    libsoup_3
    glib
    glib-networking # GIO TLS backend (GnuTLS); without it libsoup3 reports "TLS support is not available"
    gdk-pixbuf
    cairo
    dbus
    libayatana-appindicator # dlopened at runtime (tray)
    pango
    harfbuzz
    fontconfig
    freetype
    libGL
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    stdenv.cc.cc.lib # libstdc++.so.6, libgcc_s.so.1
  ];

  # A .deb is an `ar` archive; extract the data.tar.* payload.
  unpackPhase = ''
    runHook preUnpack
    ar x "$src" >/dev/null
    data_archive=$(ls data.tar.* | head -1)
    tar -xf "$data_archive"
    runHook postUnpack
  '';

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share"

    # Main binary (uses the system GTK/WebKit, so the cursor theme follows the
    # desktop session — unlike the self-contained AppImage, which bundled its
    # own GTK and could not read the host's cursor-theme config).
    install -Dm755 "usr/bin/Axolotl Launcher" "$out/bin/axolotl-launcher"

    # Desktop integration: install under canonical names and rewrite the
    # Exec/Icon to the no-space launcher name. The deb ships the desktop and
    # icons under "Axolotl Launcher" (with a space).
    install -Dm644 "usr/share/applications/Axolotl Launcher.desktop" \
      "$out/share/applications/axolotl-launcher.desktop"
    substituteInPlace "$out/share/applications/axolotl-launcher.desktop" \
      --replace-fail 'Exec="Axolotl Launcher"' 'Exec=axolotl-launcher' \
      --replace-fail 'Icon=Axolotl Launcher' 'Icon=axolotl-launcher' \
      --replace-fail 'StartupWMClass="Axolotl Launcher"' 'StartupWMClass=axolotl-launcher'
    install -Dm644 usr/share/icons/hicolor/128x128/apps/Axolotl\ Launcher.png \
      "$out/share/icons/hicolor/128x128/apps/axolotl-launcher.png"
    install -Dm644 "usr/share/icons/hicolor/256x256@2/apps/Axolotl Launcher.png" \
      "$out/share/icons/hicolor/256x256@2/apps/axolotl-launcher.png"

    # Allow the user to opt into native Wayland (default stays X11/XWayland,
    # where the cursor theme already works). GStreamer plugin path lets WebKit
    # find media elements (appsink etc.) at runtime. GIO_EXTRA_MODULES exposes
    # the GnuTLS TLS backend so libsoup3 can open https:// login pages.
    wrapProgram "$out/bin/axolotl-launcher" \
      --set-default GDK_BACKEND x11 \
      --set GST_PLUGIN_PATH "${gstPluginsPath}" \
      --suffix GIO_EXTRA_MODULES : "${glib-networking}/lib/gio/modules"

    runHook postInstall
  '';

  meta = {
    description = "Free, cross-platform Minecraft launcher built on the Modrinth ecosystem";
    homepage = "https://github.com/Mystic-Stars/Axolotl";
    changelog = "https://github.com/Mystic-Stars/Axolotl/releases/tag/v${version}";
    license = lib.licenses.gpl3Only;
    mainProgram = "axolotl-launcher";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}