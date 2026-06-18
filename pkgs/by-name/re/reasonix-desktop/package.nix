{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  copyDesktopItems,
  gdk-pixbuf,
  glib,
  gtk3,
  libsoup_3,
  makeDesktopItem,
  webkitgtk_4_1,
  wrapGAppsHook3,
}:

let
  version = "1.9.1";
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
    hash = "sha256-vRHPc72nQYqc12CFmykLyVaWebHOKLS3W8sTHScGQOM=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    wrapGAppsHook3
  ];

  buildInputs = [
    gdk-pixbuf
    glib
    gtk3
    libsoup_3
    webkitgtk_4_1
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 reasonix-desktop "$out/bin/reasonix-desktop"
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
