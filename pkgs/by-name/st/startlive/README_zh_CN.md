# startlive

> 中文（简体） · [English](README.md)

[StartLive](https://github.com/Radekyspec/StartLive)，一款绕过 B 站官方「直播姬」开播的桌面程序：从 B 站接口取回推流地址，再通过 WebSocket 驱动本机（或另一台机器上）的 OBS Studio。

当前版本：1.2.1。

## 为什么用 PyPI 源码包

上游只提供 Windows 与 macOS 安装包，Linux 必须从源码构建。源码取自 PyPI 而非 GitHub tag：tag `1.2.1` 里根本没有 `pyproject.toml`，该 tag 无法作为 Python 包构建。PyPI 与 tag 并不同步。

## 打包说明

- 除 `PyQtDarkTheme-fork` 外，所有运行时依赖都在 nixpkgs 中。上游把该包固定为 `~=2.3.6`，而 nixpkgs 只有原版 `pyqtdarktheme`（仍停留在 2.1.0），因此由同目录下的 `pyqtdarktheme-fork.nix` 从其 PyPI 源码包单独构建。
- 上游对 `pillow`、`requests`、`keyring`、`cryptography` 的 `~=` 版本约束由 `pythonRelaxDeps` 解除：nixpkgs 提供的版本比这些约束允许的更新，而 StartLive 用到的 API 并无变化。`velopack` 无需处理 —— 它的环境标记本就排除了 Linux。
- Qt 插件由 `qtbase` 提供（PySide6 链接了 Qt 但不会传递它）。刻意不依赖 `qtwayland`：`qtbase` 已经自带 `platforms/libqwayland.so` 以及 xdg-shell、窗饰等集成。
- `startlive` 是本包的 `mainProgram`。同时安装 desktop 文件与 512x512 图标；图标从上游的 `.ico` 中提取，因为源码包里没有其它图形资源。
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
./update.sh           # 跟随 PyPI 最新版
./update.sh 1.2.0     # 或指定版本
```

脚本还会在上游调整 `PyQtDarkTheme-fork` 约束时同步跟进，并重新构建验证。
