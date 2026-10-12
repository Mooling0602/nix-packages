{
  lib,
  stdenv,
  fetchurl,
  alsa-lib,
  autoPatchelfHook,
  bubblewrap,
  copyDesktopItems,
  gdk-pixbuf,
  glib,
  gst_all_1,
  gtk3,
  libsoup_3,
  makeDesktopItem,
  nspr,
  nss,
  webkitgtk_4_1,
  wrapGAppsHook3,
}:

let
  version = "1.39.8";
  gstPlugins = [
    gst_all_1.gst-plugins-base
  ];
  appIcon = fetchurl {
    url = "https://raw.githubusercontent.com/esengine/DeepSeek-Reasonix/desktop-v${version}/desktop/build/appicon.png";
    hash = "sha256-A6hFLGz8NmiFual/1ZR9syXQgxsnQBM1YxP9bPaTV/8=";
  };
in
stdenv.mkDerivation {
  pname = "reasonix-desktop";
  inherit version;

  src = fetchurl {
    url = "https://github.com/esengine/DeepSeek-Reasonix/releases/download/desktop-v${version}/Reasonix-linux-amd64.tar.gz";
    hash = "sha256-yARQMLefnx5R06q7XsybmrT4iMsMLWtghFeogWtb51s=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    wrapGAppsHook3
  ];

  # Electron's runtime: the bundled Chromium shell in `app/` links these, and
  # autoPatchelfHook needs them resolvable from the build inputs.
  buildInputs = [
    alsa-lib
    gdk-pixbuf
    glib
    gtk3
    libsoup_3
    nspr
    nss
    webkitgtk_4_1
  ];

  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ bubblewrap ]})
    gappsWrapperArgs+=(--prefix GST_PLUGIN_SYSTEM_PATH_1_0 : ${lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" gstPlugins})
  '';

  # The release tarball is not a single static binary: `reasonix-desktop` is a
  # small Go launcher that looks for the Electron shell ("app/") *beside itself*,
  # so the whole payload has to stay together in one directory and `bin` must
  # link into it rather than point at a lone copied binary.
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/reasonix-desktop" "$out/bin" "$out/share/icons/hicolor/512x512/apps"
    cp -r . "$out/lib/reasonix-desktop/"
    # stdenv drops its exported build environment next to the unpacked sources.
    rm -f "$out/lib/reasonix-desktop/env-vars"
    ln -s "$out/lib/reasonix-desktop/reasonix-desktop" "$out/bin/reasonix-desktop"
    install -Dm644 ${appIcon} "$out/share/icons/hicolor/512x512/apps/reasonix-desktop.png"
    runHook postInstall
    substituteInPlace "$out/share/applications/reasonix-desktop.desktop" \
      --replace-fail "Exec=reasonix-desktop" "Exec=$out/bin/reasonix-desktop"
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "reasonix-desktop";
      desktopName = "Reasonix Desktop";
      exec = "reasonix-desktop";
      icon = "reasonix-desktop";
      terminal = false;
      categories = [
        "Development"
        "Utility"
      ];
    })
  ];

  meta = {
    description = "Desktop app for the DeepSeek-Reasonix reasoning enhancer";
    homepage = "https://github.com/esengine/DeepSeek-Reasonix";
    license = lib.licenses.mit;
    mainProgram = "reasonix-desktop";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
