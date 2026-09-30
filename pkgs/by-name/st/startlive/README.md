# startlive

> English · [中文（简体）](README_zh_CN.md)

[StartLive](https://github.com/Radekyspec/StartLive) starts Bilibili live streams without
Bilibili's official LiveHime client: it fetches the push URL from Bilibili's API and drives a
local OBS Studio (or one on another machine) over its WebSocket interface.

Current version: 1.2.1.

## Why the PyPI sdist

Upstream only ships installers for Windows and macOS, so Linux has to build from source. The
source comes from PyPI rather than the GitHub tag: tag `1.2.1` contains no `pyproject.toml` at
all, so that tag cannot be built as a Python package. PyPI and the tags are not in sync.

## Packaging notes

- Every runtime dependency is in nixpkgs except `PyQtDarkTheme-fork`, which upstream pins at
  `~=2.3.6`. nixpkgs only carries the original `pyqtdarktheme`, still at 2.1.0, so the fork is
  built from its own PyPI sdist by `pyqtdarktheme-fork.nix` next to this file.
- `pythonRelaxDeps` drops the version bounds upstream puts on `pillow`, `requests`, `keyring` and
  `cryptography`, because nixpkgs ships newer releases than those `~=` pins admit. The APIs
  StartLive uses are unchanged. `velopack` needs no such treatment — its environment marker
  already excludes Linux.
- Qt plugins come from `qtbase`, which PySide6 links but does not propagate. `qtwayland` is
  deliberately not a dependency: `qtbase` already ships `platforms/libqwayland.so` together with
  the xdg-shell and decoration integrations.
- The `startlive` command is the package's `mainProgram`. A desktop entry and a 512x512 icon are
  installed as well; the icon is extracted from the `.ico` upstream ships, as the sdist contains
  no other artwork.
- Credentials are stored in the system keyring, so a running Secret Service implementation
  (gnome-keyring, KWallet, …) is needed on Linux.

## Usage

```bash
startlive                                          # start the GUI
startlive --version
startlive --web.host 0.0.0.0 --web.port 8080
```

## Known issue

Under headless testing (`QT_QPA_PLATFORM=offscreen`, isolated `HOME`), the application segfaults
intermittently while the QR login flow updates the UI. `QObject::~QObject` crashes inside a
`DeferredDelete` delivery — the classic double-destroy of a Qt object owned by both C++ and
Python. It reproduces on Python 3.12 and 3.14 alike, so it is an application-level race rather
than a packaging artefact. It has not been reproduced on a real display yet.

## Update

```bash
./update.sh           # track the latest PyPI release
./update.sh 1.2.0     # or pin a specific version
```

The script also follows the `PyQtDarkTheme-fork` pin when upstream raises it, then rebuilds to
verify.
