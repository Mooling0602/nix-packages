{
  lib,
  stdenv,
  fetchurl,
  buildFHSEnv,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libgbm,
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
  xdg-utils,
  zlib,
}:

let
  version = "26.909.91205";

  # The unpacked upstream app, deliberately left unpatched: every binary in it
  # resolves its libraries against the FHS sandbox that `buildFHSEnv` below
  # puts around it.
  app = stdenv.mkDerivation {
    pname = "xiaomi-mimo-desktop-app";
    inherit version;

    # Upstream only links the Windows and macOS installers on its download page,
    # but the official Linux build is published on the same download CDN as a
    # Debian package. The URL is versioned: there is no `latest` alias and no
    # update feed for the Linux build. The AUR package `mimo-desktop` tracks the
    # same artifact.
    src = fetchurl {
      url = "https://mimocode-cdn.xiaomimimo.com/mimocode/mimodesktop/XiaomiMiMo-${version}-x64.deb";
      hash = "sha256-AK0MN/g9vkEYvyuPTD+pIIsbOvlRm/eyG6sFMIgFj/c=";
    };

    # Prebuilt Electron tree; re-stripping it is pointless and risky.
    dontStrip = true;

    # Extract into a fixed directory so that the phases below never depend on
    # whatever working directory stdenv leaves behind after a custom unpackPhase.
    unpackPhase = ''
      runHook preUnpack
      mkdir -p "$NIX_BUILD_TOP/unpacked"
      cd "$NIX_BUILD_TOP/unpacked"
      ar x "$src"
      tar -x --no-same-owner --no-same-permissions -f data.tar.xz
      cd "$NIX_BUILD_TOP"
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      appRoot="$NIX_BUILD_TOP/unpacked"

      mkdir -p "$out/share"
      cp -r "$appRoot/opt/Xiaomi MiMo" "$out/share/xiaomi-mimo-desktop"

      mkdir -p "$out/bin"
      ln -s "$out/share/xiaomi-mimo-desktop/xiaomi-mimo-desktop" "$out/bin/xiaomi-mimo-desktop"

      mkdir -p "$out/share/icons"
      cp -r "$appRoot"/usr/share/icons/. "$out/share/icons/"

      install -Dm644 "$appRoot/usr/share/applications/xiaomi-mimo.desktop" \
        "$out/share/applications/xiaomi-mimo.desktop"
      substituteInPlace "$out/share/applications/xiaomi-mimo.desktop" \
        --replace-fail 'Exec="/opt/Xiaomi MiMo/xiaomi-mimo-desktop" %U' \
          'Exec='"$out"'/bin/xiaomi-mimo-desktop %U'

      install -Dm644 "$appRoot/usr/share/doc/xiaomi-mimo-desktop/changelog.gz" \
        "$out/share/doc/xiaomi-mimo-desktop/changelog.gz"

      # Upstream's Linux build ships neither the `node-machine-id` package in
      # app.asar/node_modules nor a bundled implementation, yet the login flow
      # requires it to derive the Xiaomi passport deviceId. The require always
      # fails there, and every login dies with passport 20014 ("参数错误").
      # Node's module resolution walks out of the asar up to
      # `resources/node_modules`, so dropping a shim module in there restores
      # the login without repacking the asar archive. The shim prefers a real
      # system machine id and otherwise generates one and persists it in the
      # app's config directory.
      install -Dm644 ${./node-machine-id-shim}/index.js \
        "$out/share/xiaomi-mimo-desktop/resources/node_modules/node-machine-id/index.js"
      install -Dm644 ${./node-machine-id-shim}/package.json \
        "$out/share/xiaomi-mimo-desktop/resources/node_modules/node-machine-id/package.json"

      # The bundled CPython runtime ships a terminfo database whose alias
      # entries are symlinks whose targets are absent from the upstream deb.
      # They are dangling there already; drop them to satisfy the broken-symlink
      # output check.
      find "$out" -xtype l -delete

      runHook postInstall
    '';
  };
in
buildFHSEnv {
  pname = "xiaomi-mimo-desktop";
  inherit version;

  # Why an FHS sandbox: the app ships its own CPython runtime and a set of
  # native Node modules, and its agent installs third-party Python wheels at
  # runtime. None of that can be rewritten for the Nix store after the fact
  # (autoPatchelf breaks the bundled runtime's glibc symbol versions, and
  # runtime-installed wheels cannot be patched at all), so the whole app runs
  # unpatched inside a bubblewrap FHS root where every binary resolves against
  # the standard `/usr/lib` layout, exactly as on a traditional distribution.
  targetPkgs = pkgs: [
    app
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libgbm
    libglvnd
    libnotify
    libsecret
    libuuid
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxscrnsaver
    libxshmfence
    libxtst
    libxkbfile
    mesa
    nspr
    nss
    pango
    systemd
    wayland
    xdg-utils
    zlib
    # libstdc++/libgcc_s for native Python wheels the agent installs at runtime.
    pkgs.stdenv.cc.cc.lib
  ];

  # The upstream setuid `chrome-sandbox` cannot be honoured from the Nix store,
  # so the Chromium sandbox is disabled, as for other repackaged Electron apps.
  runScript = "xiaomi-mimo-desktop --no-sandbox --password-store=gnome-libsecret";

  extraInstallCommands = ''
    install -Dm644 ${app}/share/applications/xiaomi-mimo.desktop \
      $out/share/applications/xiaomi-mimo.desktop
    substituteInPlace $out/share/applications/xiaomi-mimo.desktop \
      --replace-fail "Exec=${app}/bin/xiaomi-mimo-desktop %U" \
        'Exec='"$out"'/bin/xiaomi-mimo-desktop %U'
    mkdir -p $out/share/icons
    cp -r ${app}/share/icons/. $out/share/icons/
  '';

  meta = {
    description = "Xiaomi MiMo desktop client with the built-in AI assistant";
    longDescription = ''
      Xiaomi MiMo Desktop (小米 MiMo 桌面客户端) is Xiaomi's official AI desktop
      agent: it takes multi-format materials and natural-language goals, breaks
      them into tasks, drives tools, and delivers editable office documents,
      slides, designs, code and other artifacts.

      This package is built from the official Linux `.deb`, which upstream does
      not link on its download page, and runs it inside a bubblewrap FHS
      sandbox so that its bundled Python runtime, native Node modules and
      runtime-installed Python wheels all work as on a traditional
      distribution. It is closed-source commercial software; an Internet
      connection and a Xiaomi MiMo account are required to use it.
    '';
    homepage = "https://mimo.xiaomimimo.com/desktop/";
    license = lib.licenses.unfree;
    mainProgram = "xiaomi-mimo-desktop";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
