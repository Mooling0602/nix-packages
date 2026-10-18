{
  lib,
  fetchFromGitHub,
  icoutils,
  copyDesktopItems,
  makeDesktopItem,
  python3Packages,
  qt6,
}:

let
  pyqtdarktheme-fork = python3Packages.callPackage ./pyqtdarktheme-fork.nix { };
in

python3Packages.buildPythonApplication (finalAttrs: {
  pname = "startlive";
  version = "1.3.0";
  pyproject = true;

  # Built from the release tag instead of PyPI: upstream's sdist is published
  # by a workflow that waits for manual approval, so it can lag the release by
  # days. Since 1.3.0 the tag itself carries `pyproject.toml`, a self-contained
  # `startlive/` package and `requirements.txt`, so it is installable as-is.
  src = fetchFromGitHub {
    owner = "Radekyspec";
    repo = "StartLive";
    tag = finalAttrs.version;
    hash = "sha256-ZZa/r9iNSCNudPqx6IKhdICqRPwHlbzKABXkd6pxfrg=";
  };

  build-system = [ python3Packages.setuptools ];

  dependencies =
    (with python3Packages; [
      pyside6
      pillow # PIL, also the image backend of qrcode
      qrcode
      requests
      pysocks # requests[socks]
      brotli # Brotli>=1.2,<2
      obsws-python
      keyring # brings in secretstorage, the Secret Service backend
      darkdetect
      semver
      cryptography
      # Upstream asks for protobuf>=5.29,<7; nixpkgs' default is 7.x, so use
      # the 6.x attribute instead of dropping the upper bound.
      protobuf6 # only imported when the PK window is opened
    ])
    # The `pk` extra. Only imported once the PK window is opened, so a missing
    # dependency degrades that feature instead of breaking startup. Both pins
    # match nixpkgs exactly.
    ++ (with python3Packages; [
      aiortc
      aioice
      certifi
    ])
    ++ [ pyqtdarktheme-fork ];

  # nixpkgs ships newer releases than the `~=` pins in upstream's
  # requirements.txt. Only the version bounds differ; the APIs StartLive uses
  # are unchanged. The `velopack` pin is skipped automatically, because its
  # environment marker excludes Linux.
  pythonRelaxDeps = [
    "pyside6" # ~=6.12.0 vs nixpkgs 6.11.x
    "pillow" # ~=12.2.0
    "requests" # ~=2.32.5
    "keyring" # ~=25.6.0
    "cryptography" # ~=49.0.0
  ];

  nativeBuildInputs = [
    copyDesktopItems
    icoutils
    qt6.wrapQtAppsHook
  ];

  # PySide6 links Qt but does not propagate it, so qtbase is what puts the Qt
  # plugins (platform plugins, image formats) in the runtime closure.
  # qtwayland is deliberately absent: qtbase already ships
  # `platforms/libqwayland.so` plus the xdg-shell and decoration integrations,
  # and qtwayland itself carries no client platform plugin.
  buildInputs = [ qt6.qtbase ];

  pythonImportsCheck = [
    "StartLive"
    "startlive.core.constant"
  ];

  postInstall = ''
    # Upstream only ships Windows-format .ico files, each holding a single
    # 512x512 PNG payload, so extracting one is lossless. Two variants exist and
    # both are identical to what 1.3.0 ships.
    #
    # `icon_left.ico` is installed rather than `icon_left_macOS.ico` on purpose:
    # the macOS variant is the same artwork on a rounded-square plate with a drop
    # shadow, following Apple's icon template. StartLive picks that variant for
    # every non-Windows platform (`StartLive.py:85-91`), but Linux desktops mask
    # launcher icons themselves, so the plate would end up doubled. The plain
    # variant is also what upstream uses for its tray icon on all platforms
    # (`startlive/PySide/window/main_window.py`).
    icotool --extract --output=. startlive/resources/icon_left.ico
    install -Dm644 icon_left_1_512x512x32.png \
      "$out/share/icons/hicolor/512x512/apps/startlive.png"

    install -Dm644 LICENSE -t "$out/share/licenses/startlive"
    install -Dm644 LICENSE-ARTWORK -t "$out/share/licenses/startlive"
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "startlive";
      desktopName = "StartLive";
      genericName = "Bilibili live streaming tool";
      comment = "Start Bilibili live streams without the official LiveHime client";
      exec = "startlive %u";
      icon = "startlive";
      terminal = false;
      categories = [
        "AudioVideo"
        "Network"
        "Video"
      ];
      keywords = [
        "bilibili"
        "rtmp"
        "startlive"
        "推流"
        "直播"
      ];
      startupWMClass = "startlive";
    })
  ];

  meta = {
    description = "Start Bilibili live streams without the official LiveHime client";
    longDescription = ''
      StartLive fetches the RTMP/SRT push URL from Bilibili's API and drives a
      local OBS Studio over its WebSocket interface, so a stream can be started
      without installing Bilibili's official LiveHime client. It also supports
      QR-code login, cover and title management, a built-in web server, and
      connecting to OBS running on another machine.

      The bundled artwork (the application logo) is not covered by the GPL;
      see LICENSE-ARTWORK in the installed license directory.
    '';
    homepage = "https://github.com/Radekyspec/StartLive";
    changelog = "https://github.com/Radekyspec/StartLive/releases/tag/${finalAttrs.version}";
    license = lib.licenses.gpl3Only;
    mainProgram = "startlive";
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
})
