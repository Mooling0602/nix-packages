# startlive

> English · [中文（简体）](README_zh_CN.md)

[StartLive](https://github.com/Radekyspec/StartLive) starts Bilibili live streams without
Bilibili's official LiveHime client: it fetches the push URL from Bilibili's API and drives a
local OBS Studio (or one on another machine) over its WebSocket interface.

Current version: 1.3.0.

## Why the GitHub tag

Upstream only ships installers for Windows and macOS, so Linux has to build from source. The
source comes from the release tag: since `1.3.0` the tag carries `pyproject.toml`, a
self-contained `startlive/` package and `requirements.txt`, so it is installable as-is. It is
preferred over the PyPI sdist because upstream publishes that sdist from a workflow that waits
for manual approval, so PyPI can trail the GitHub release by days. Tags before `1.3.0` are not
usable at all — `1.2.1` has no `pyproject.toml`.

## Packaging notes

- Every runtime dependency is in nixpkgs except `PyQtDarkTheme-fork`, which upstream pins at
  `~=2.3.6`. nixpkgs only carries the original `pyqtdarktheme`, still at 2.1.0, so the fork is
  built from its own PyPI sdist by `pyqtdarktheme-fork.nix` next to this file.
- `protobuf` is pinned to the `protobuf6` attribute instead of relaxing the `<7` bound upstream
  declares: nixpkgs' default `protobuf` is 7.x.
- The optional `pk` extra (`aiortc`, `aioice`, `certifi`) is included so the PK window works.
  Those pins happen to match nixpkgs exactly. Both it and `protobuf` are only imported once the
  PK window is opened, so they cannot break startup.
- `pythonRelaxDeps` drops the version bounds upstream puts on `pyside6`, `pillow`, `requests`,
  `keyring` and `cryptography`, because nixpkgs ships newer releases than those `~=` pins admit.
  The APIs StartLive uses are unchanged. `velopack` needs no such treatment — its environment
  marker already excludes Linux.
- Qt plugins come from `qtbase`, which PySide6 links but does not propagate. `qtwayland` is
  deliberately not a dependency: `qtbase` already ships `platforms/libqwayland.so` together with
  the xdg-shell and decoration integrations.
- `qtsvg` is a hard requirement on top of `qtbase`. The sidebar icons are SVG and Qt resolves them
  through its `imageformats` plugin, which `qtbase` does not provide (it only bundles gif/ico/jpeg),
  so `QIcon("…svg")` silently comes back null and those buttons render empty. PySide6 pulls `qtsvg`
  in as a library dependency, but that does not expose the plugin.
- `preFixup` forwards `qtWrapperArgs` to `makeWrapperArgs`. `wrapQtAppsHook` only wraps ELF
  executables, and at that point `bin/startlive` is still a `#!python` script, so the hook's
  `QT_PLUGIN_PATH` would otherwise be dropped — taking the SVG plugin with it.
- The `startlive` command is the package's `mainProgram`. A desktop entry and a 512x512 icon are
  installed as well; the icon is extracted from the `.ico` upstream ships, as the source tree
  contains no other artwork. The plain `icon_left.ico` is used rather than upstream's
  `icon_left_macOS.ico`: the latter is the same artwork on a rounded plate meant for macOS, which
  Linux desktops would mask a second time.
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
./update.sh           # track the latest GitHub release
./update.sh 1.3.0     # or pin a specific version
```

The script also follows the `PyQtDarkTheme-fork` pin when upstream raises it, then rebuilds to
verify.
