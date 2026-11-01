{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  zstd,
  libxkbcommon,
  libxcb,
  wayland,
  libGL,
  vulkan-loader,
  git,
  curl,
  xdg-utils,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "elyterminal";
  version = "0.2.1";

  src = fetchurl {
    url = "https://github.com/ELY-Open-Source/ELYTerminal/releases/download/v${finalAttrs.version}/elyterminal_${finalAttrs.version}_amd64.deb";
    hash = "sha256-FfeRU7KZdLFo5Y8/FcEKN3eRAgGObcYBR+8VklmgzxQ=";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper zstd ];
  buildInputs = [ libxkbcommon libxcb stdenv.cc.cc.lib ];

  unpackPhase = ''
    runHook preUnpack
    ar x "$src"
    tar -xf data.tar.*
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 usr/bin/elyterminal "$out/bin/elyterminal"
    cp -r usr/share "$out/share"
    wrapProgram "$out/bin/elyterminal" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ wayland libGL vulkan-loader ]}" \
      --suffix PATH : "${lib.makeBinPath [ git curl xdg-utils ]}"
    runHook postInstall
  '';

  meta = {
    description = "GPU-rendered terminal built with GPUI and Ely";
    homepage = "https://github.com/ELY-Open-Source/ELYTerminal";
    changelog = "https://github.com/ELY-Open-Source/ELYTerminal/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "elyterminal";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
})
