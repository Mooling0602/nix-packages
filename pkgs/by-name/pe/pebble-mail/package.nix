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
  openssl,
  gst_all_1,
}:

let
  gstreamer = gst_all_1.gstreamer;
  gst-plugins-base = gst_all_1.gst-plugins-base;
  gst-plugins-good = gst_all_1.gst-plugins-good;
  gst-plugins-bad = gst_all_1.gst-plugins-bad;

  # GStreamer plugin search path. WebKit instantiates media elements via
  # GStreamer; without this, embedded audio/video in HTML mail fails with
  # "GStreamer element appsink not found".
  gstPluginsPath = lib.makeSearchPath "lib/gstreamer-1.0" [
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
  ];
in

stdenv.mkDerivation (finalAttrs: {
  pname = "pebble-mail";
  version = "0.1.4";

  src = fetchurl {
    url = "https://github.com/QingJ01/Pebble/releases/download/v${finalAttrs.version}/Pebble_${finalAttrs.version}_amd64.deb";
    hash = "sha256-wqouEy1OIMY+JoBwJ8fgaYbr5wCJMMoo+O9Zf+6KpSA=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    webkitgtk_4_1
    gtk3
    libsoup_3
    glib
    glib-networking # GIO TLS backend; WebKit loads remote images over https via libsoup3
    gdk-pixbuf
    cairo
    dbus
    libayatana-appindicator # dlopened at runtime (tray)
    pango
    harfbuzz
    fontconfig
    freetype
    libGL
    openssl # libssl.so.3/libcrypto.so.3, used by the native-tls fallback for legacy POP3/IMAP servers
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

  # The payload is installed verbatim: the binary stays `pebble` and the
  # desktop entry / icons keep their upstream names (Exec=pebble, Icon=pebble
  # already match, so no rewriting is needed). Only the Nix attribute name
  # differs (`pebble-mail`, to avoid clashing with nixpkgs' letsencrypt pebble).
  installPhase = ''
    runHook preInstall

    install -Dm755 usr/bin/pebble "$out/bin/pebble"

    install -Dm644 usr/share/applications/Pebble.desktop \
      "$out/share/applications/Pebble.desktop"
    install -Dm644 usr/share/icons/hicolor/32x32/apps/pebble.png \
      "$out/share/icons/hicolor/32x32/apps/pebble.png"
    install -Dm644 usr/share/icons/hicolor/128x128/apps/pebble.png \
      "$out/share/icons/hicolor/128x128/apps/pebble.png"
    install -Dm644 "usr/share/icons/hicolor/256x256@2/apps/pebble.png" \
      "$out/share/icons/hicolor/256x256@2/apps/pebble.png"
    install -Dm644 usr/share/icons/hicolor/512x512/apps/pebble.png \
      "$out/share/icons/hicolor/512x512/apps/pebble.png"

    # GStreamer plugin path lets WebKit find media elements (appsink etc.) at
    # runtime. GIO_EXTRA_MODULES exposes the GnuTLS TLS backend so libsoup3
    # can fetch remote https resources (remote images in HTML mail).
    # LD_LIBRARY_PATH exposes libayatana-appindicator3.so.1, which
    # libappindicator-sys dlopens for the tray icon: autoPatchelfHook only
    # patches DT_NEEDED entries, so dlopened libs must be on the loader path
    # (same treatment as Tauri/Electron apps in nixpkgs).
    wrapProgram "$out/bin/pebble" \
      --set GST_PLUGIN_PATH "${gstPluginsPath}" \
      --suffix GIO_EXTRA_MODULES : "${glib-networking}/lib/gio/modules" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libayatana-appindicator ]}"

    runHook postInstall
  '';

  meta = {
    description = "Local-first desktop email client built with Rust, Tauri, and React";
    longDescription = ''
      Pebble is a small yet beautiful local-first desktop mail client. It keeps
      mail data, the search index, attachments, rules, and application settings
      on your device by default, and supports Gmail, IMAP, POP3, and
      experimental Outlook accounts.
    '';
    homepage = "https://github.com/QingJ01/Pebble";
    changelog = "https://github.com/QingJ01/Pebble/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "pebble";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
})
