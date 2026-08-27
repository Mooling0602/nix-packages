{
  lib,
  stdenv,
  fetchurl,
  buildFHSEnv,
  writeShellScript,

  # Launcher GUI (Tauri / WebKitGTK)
  webkitgtk_4_1,
  gtk3,
  libsoup_3,
  glib,
  glib-networking,
  gdk-pixbuf,
  cairo,
  pango,
  harfbuzz,
  fontconfig,
  freetype,
  dbus,
  libayatana-appindicator,
  libGL,
  gst_all_1,
  dconf,
  bubblewrap,
  zlib,
  expat,
  libdrm,
  libxkbcommon,

  # Minecraft runtime (mirrors prismlauncher's runtime library list)
  alsa-lib,
  flite,
  gamemode,
  glfw3-minecraft,
  libdecor,
  libjack2,
  libpulseaudio,
  libusb1,
  libx11,
  libxcursor,
  libxext,
  libxi,
  libxrandr,
  libxrender,
  libxtst,
  libxxf86vm,
  openal,
  pciutils,
  pipewire,
  udev,
  vulkan-loader,
  wayland,
  xrandr,

  # Fallback JVM exposed as /usr/bin/java; the launcher auto-downloads the
  # exact JRE each instance needs (which also runs fine inside the sandbox).
  jdk21,
}:

let
  version = "1.9.0";

  src = fetchurl {
    url = "https://github.com/Mystic-Stars/Axolotl/releases/download/v${version}/Axolotl.Launcher_${version}_amd64.deb";
    hash = "sha256-qwKsrC9a+1QHAgCVCcn4HXfujiqiVFA4RvsM6hvQZfQ=";
  };

  # The raw .deb payload, unpacked. The binary is intentionally NOT patched:
  # it is only ever executed inside the FHS sandbox below, where every soname
  # it needs — and every soname the launcher's downloaded Java runtimes, LWJGL
  # natives and mod-provided native libraries need — resolves through /usr/lib
  # and the ldconfig cache. That is what makes dependency-heavy mods work.
  axolotl-launcher-unwrapped = stdenv.mkDerivation {
    pname = "axolotl-launcher-unwrapped";
    inherit version src;

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

      mkdir -p "$out/libexec" "$out/share"

      # Main binary. Not wrapped or patched: it runs inside the FHS env.
      install -Dm755 "usr/bin/Axolotl Launcher" "$out/libexec/axolotl-launcher"

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

    meta = {
      description = "Unpacked .deb payload of Axolotl Launcher (only runnable inside its FHS env)";
      homepage = "https://github.com/Mystic-Stars/Axolotl";
      license = lib.licenses.gpl3Only;
      platforms = [ "x86_64-linux" ];
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  };
in
buildFHSEnv {
  pname = "axolotl-launcher-bin";
  inherit version;

  # Everything the launcher GUI links against, plus the full Minecraft runtime
  # stack (same set prismlauncher ships): audio servers, X11/Wayland client
  # libraries, GL/Vulkan loaders, udev, TTS, gamemode, controller support, and
  # the helper binaries oshi (lspci) and LWJGL 2.x (xrandr) shell out to.
  # zlib/expat/freetype/fontconfig are here for the *downloaded* JREs and
  # native payloads, which resolve sonames through the ldconfig cache.
  targetPkgs =
    pkgs:
    [
      # Launcher GUI
      webkitgtk_4_1
      gtk3
      libsoup_3
      glib
      glib-networking # GIO GnuTLS backend (libsoup3 TLS)
      gdk-pixbuf
      cairo
      pango
      harfbuzz
      fontconfig
      freetype
      dbus
      libayatana-appindicator # dlopened for the tray icon
      libGL
      gst_all_1.gstreamer # WebKit media playback
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
      gst_all_1.gst-plugins-bad
      dconf # GSettings backend for GTK
      bubblewrap # WebKit's own renderer sandbox
      zlib
      expat
      libdrm
      libxkbcommon

      # Minecraft runtime
      alsa-lib
      flite # narrator (1.20+)
      gamemode.lib
      glfw3-minecraft
      libdecor
      libjack2
      libpulseaudio
      pipewire
      openal
      udev # oshi
      libusb1 # controllers
      vulkan-loader # VulkanMod's lwjgl
      wayland
      libx11
      libxcursor
      libxext
      libxi # AWT/Swing in downloaded JREs & OptiFine installer
      libxrandr
      libxrender
      libxtst
      libxxf86vm
      pciutils # oshi runs lspci
      xrandr # LWJGL [2.9.2, 3)

      jdk21
    ];

  profile = ''
    # GIO modules (glib-networking TLS, dconf GSettings backend) live in
    # /usr/lib/gio/modules inside the sandbox; GIO only finds them via
    # GIO_EXTRA_MODULES.
    export GIO_EXTRA_MODULES="/usr/lib/gio/modules''${GIO_EXTRA_MODULES:+:$GIO_EXTRA_MODULES}"

    # Expose the host's OpenGL/Vulkan driver libraries (NixOS:
    # /run/opengl-driver, bind-mounted in by bubblewrap) to every process in
    # the sandbox — the FHS equivalent of addDriverRunpath. Also lets
    # mesa/nvidia vendor libraries win over any bundled copies. Harmless on
    # hosts without it.
    export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';

  # Shell launcher: auto-detect the display protocol and set GDK_BACKEND
  # accordingly (wayland under Wayland, x11 otherwise). Users can override by
  # exporting GDK_BACKEND before launching.
  runScript = writeShellScript "axolotl-launcher" ''
    if [ -z "$GDK_BACKEND" ]; then
      if [ -n "$WAYLAND_DISPLAY" ]; then
        export GDK_BACKEND=wayland
      else
        export GDK_BACKEND=x11
      fi
    fi
    exec "${axolotl-launcher-unwrapped}/libexec/axolotl-launcher" "$@"
  '';

  executableName = "axolotl-launcher";

  extraInstallCommands = ''
    ln -s ${axolotl-launcher-unwrapped}/share $out/share
  '';

  passthru.unwrapped = axolotl-launcher-unwrapped;

  meta = {
    description = "Free, cross-platform Minecraft launcher built on the Modrinth ecosystem";
    longDescription = ''
      Axolotl Launcher, packaged from the official Linux .deb and wrapped in a
      bubblewrap FHS environment. The launcher auto-downloads Java runtimes and
      Minecraft native libraries that expect a standard Linux filesystem; the
      FHS sandbox lets those binaries — and native libraries shipped by mods —
      resolve their dependencies through /usr/lib, while GPU drivers come from
      the host's /run/opengl-driver.
    '';
    homepage = "https://github.com/Mystic-Stars/Axolotl";
    changelog = "https://github.com/Mystic-Stars/Axolotl/releases/tag/v${version}";
    license = lib.licenses.gpl3Only;
    mainProgram = "axolotl-launcher";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
