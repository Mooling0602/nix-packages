# startlive

> 中文（简体） · [English](README.md)

[StartLive](https://github.com/Radekyspec/StartLive)，一款绕过 B 站官方「直播姬」开播的桌面程序：从 B 站接口取回推流地址，再通过 WebSocket 驱动本机（或另一台机器上）的 OBS Studio。

当前版本：1.4.0。

## 为什么用 GitHub tag

上游只提供 Windows 与 macOS 安装包，Linux 必须从源码构建。源码取自 release tag：自 `1.3.0` 起，tag 自带 `pyproject.toml`、自成体系的 `startlive/` 包与 `requirements.txt`，可直接安装。不用 PyPI 源码包是因为上游的发布流程需要人工审批，PyPI 可能比 GitHub release 晚几天。`1.3.0` 之前的 tag 完全不可用 —— `1.2.1` 没有 `pyproject.toml`。

## 打包说明

- 除 `PyQtDarkTheme-fork` 外，所有运行时依赖都在 nixpkgs 中。上游把该包固定为 `~=2.3.6`，而 nixpkgs 只有原版 `pyqtdarktheme`（仍停留在 2.1.0），因此由同目录下的 `pyqtdarktheme-fork.nix` 从其 PyPI 源码包单独构建。
- `protobuf` 使用 `protobuf6` 属性而不是解除上游声明的 `<7` 约束：nixpkgs 默认的 `protobuf` 已是 7.x。
- 可选 `pk` 附加依赖（`aiortc`、`aioice`、`certifi`）也一并打包，使 PK 窗口可用；这些 pin 恰好与 nixpkgs 完全一致。它与 `protobuf` 都只在打开 PK 窗口时才会导入，不影响启动。
- 上游对 `pyside6`、`pillow`、`requests`、`keyring`、`cryptography` 的 `~=` 版本约束由 `pythonRelaxDeps` 解除：nixpkgs 提供的版本比这些约束允许的更新，而 StartLive 用到的 API 并无变化。`velopack` 无需处理 —— 它的环境标记本就排除了 Linux。
- Qt 插件由 `qtbase` 提供（PySide6 链接了 Qt 但不会传递它）。刻意不依赖 `qtwayland`：`qtbase` 已经自带 `platforms/libqwayland.so` 以及 xdg-shell、窗饰等集成。
- 在 `qtbase` 之外，`qtsvg` 是硬性依赖。侧边栏图标是 SVG，Qt 需要经由 `imageformats` 插件才能渲染，而 `qtbase` 只打包了 gif/ico/jpeg，于是 `QIcon("…svg")` 会静默返回空图标，那些按钮就显示空白。PySide6 会把 `qtsvg` 作为库依赖拉进来，但并不会暴露插件。
- `preFixup` 把 `qtWrapperArgs` 并入 `makeWrapperArgs`。`wrapQtAppsHook` 只处理 ELF 可执行文件，而在那个阶段 `bin/startlive` 还是 `#!python` 脚本，因此 hook 设置的 `QT_PLUGIN_PATH` 会被丢弃，SVG 插件也就一起丢了。
- `startlive` 是本包的 `mainProgram`。同时安装 desktop 文件与 512x512 图标；图标从上游的 `.ico` 中提取，因为源码树里没有其它图形资源。用的是普通的 `icon_left.ico` 而非上游的 `icon_left_macOS.ico`：后者是同一份图案加上了 macOS 风格的圆角底板，而 Linux 桌面会再裁一次。
- 凭据存放在系统 keyring 中，因此 Linux 上需要运行 Secret Service 实现（gnome-keyring、KWallet 等）。

## 使用方法

```bash
startlive                                          # 启动图形界面
startlive --version
startlive --web.host 0.0.0.0 --web.port 8080
```

## 已知问题

在无头环境下测试时（`QT_QPA_PLATFORM=offscreen`、独立 `HOME`），程序在扫码登录流程刷新界面的过程中会偶发段错误：`QObject::~QObject` 在 `DeferredDelete` 事件投递中崩溃，即 Qt 对象同时被 C++ 与 Python 持有导致的重复析构。Python 3.12 与 3.14 上都能复现，属于应用层竞态而非打包问题。目前尚未在真实显示器上复现。

## 更新

```bash
./update.sh           # 跟随 GitHub 最新 release
./update.sh 1.3.0     # 或指定版本
```

脚本还会在上游调整 `PyQtDarkTheme-fork` 约束时同步跟进，并重新构建验证。
