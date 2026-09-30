{
  lib,
  fetchPypi,
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
  version = "1.2.1";
  pyproject = true;

  # Built from the PyPI sdist: the GitHub tag `1.2.1` predates the
  # `pyproject.toml` that upstream builds the distribution from, so that tag
  # is not installable as a Python package at all.
  src = fetchPypi {
    inherit (finalAttrs) pname version;
    hash = "sha256-yHtehLdkb+/TxvUA/2cw8by3Ej1//BvBsJvxRci4gAc=";
  };

  build-system = [ python3Packages.setuptools ];

  dependencies =
    (with python3Packages; [
      pyside6
      pillow # PIL, also the image backend of qrcode
      qrcode
      requests
      pysocks # requests[socks]
      obsws-python
      keyring # brings in secretstorage, the Secret Service backend
      darkdetect
      semver
      cryptography
    ])
    ++ [ pyqtdarktheme-fork ];

  # nixpkgs ships newer releases than the `~=` pins in upstream's
  # requirements.txt. Only the version bounds differ; the APIs StartLive uses
  # are unchanged. The `velopack` pin is skipped automatically, because its
  # environment marker excludes Linux.
  pythonRelaxDeps = [
    "pillow"
    "requests"
    "keyring"
    "cryptography"
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
    "src.core.constant"
  ];

  postInstall = ''
    # Upstream only ships Windows-format .ico files. The one used on
    # non-Windows platforms holds a single 512x512 PNG payload, so extracting
    # it is lossless.
    icotool --extract --output=. resources/icon_left_macOS.ico
    install -Dm644 icon_left_macOS_1_512x512x32.png \
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
