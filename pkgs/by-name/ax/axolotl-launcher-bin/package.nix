{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook4,
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
  version = "1.8.14";

  src = fetchurl {
    url = "https://github.com/Mystic-Stars/Axolotl/releases/download/v${version}/Axolotl.Launcher_${version}_amd64.deb";
    hash = "sha256-6HJqAYHIbqKoUfdLyB+/YocwbGwtJwC6YN8PG/yx1IA=";
  };

in
stdenv.mkDerivation {
  inherit pname version;

  src = src;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook4
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

    mkdir -p "$out/bin" "$out/libexec" "$out/share"

    # Main binary (uses the system GTK/WebKit, so the cursor theme follows the
    # desktop session — unlike the self-contained AppImage, which bundled its
    # own GTK and could not read the host's cursor-theme config).
    install -Dm755 "usr/bin/Axolotl Launcher" "$out/libexec/axolotl-launcher"

      # Shell launcher: auto-detect the display protocol and set GDK_BACKEND
      # accordingly (wayland under Wayland, x11 otherwise). Users can override
      # by exporting GDK_BACKEND before launching. The real binary in libexec/
      # is wrapped by wrapGAppsHook4 in postFixup.
      cat > "$out/bin/axolotl-launcher" <<EOF
#!/bin/sh
if [ -z "\$GDK_BACKEND" ]; then
  if [ -n "\$WAYLAND_DISPLAY" ]; then
    export GDK_BACKEND=wayland
  else
    export GDK_BACKEND=x11
  fi
fi
exec "$out/libexec/axolotl-launcher" "\$@"
EOF
      chmod +x "$out/bin/axolotl-launcher"

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

    runHook postInstall
  '';

  # Custom wrapper args for wrapGAppsHook4. GIO_EXTRA_MODULES for the GnuTLS
  # TLS backend is injected automatically by the hook's find_gio_modules, so
  # it is not repeated here. GDK_BACKEND is handled by the shell launcher in
  # bin/ (auto-detects Wayland vs X11), so it is not set here either.
  preFixup = ''
    gappsWrapperArgs+=(
      # Let WebKit find GStreamer media elements (appsink etc.) at runtime.
      --set GST_PLUGIN_PATH "${gstPluginsPath}"
      # Expose libayatana-appindicator3.so.1, which libappindicator-sys
      # dlopens for the tray icon: autoPatchelfHook only patches DT_NEEDED
      # entries, so dlopened libs must be on the loader path (same treatment
      # as Tauri/Electron apps in nixpkgs).
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libayatana-appindicator ]}"
    )
  '';

  # Prevent wrapGAppsHook4 from auto-wrapping the shell launcher in bin/; we
  # manually wrap only the real binary in libexec/.
  dontWrapGApps = true;

  postFixup = ''
    wrapGApp "$out/libexec/axolotl-launcher"
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
