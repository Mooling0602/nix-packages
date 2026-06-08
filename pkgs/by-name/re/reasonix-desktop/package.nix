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
  version = "1.3.0";
in
stdenv.mkDerivation {
  pname = "reasonix-desktop";
  inherit version;

  src = fetchurl {
    url = "https://github.com/esengine/DeepSeek-Reasonix/releases/download/desktop-v${version}/Reasonix-linux-amd64.tar.gz";
    hash = "sha256-FEYNFBF/cP42v6lSbksHl1hACbGdiQ2LN7TjxHkcd/U=";
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
    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "reasonix-desktop";
      desktopName = "Reasonix Desktop";
      exec = "reasonix-desktop";
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
