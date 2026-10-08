# xiaomi-mimo-desktop

> 中文（简体） · [English](README.md)

[Xiaomi MiMo Desktop](https://mimo.xiaomimimo.com/desktop/)（小米 MiMo 桌面客户端）——
小米官方的 AI 桌面智能体应用，面向办公、设计、编程与多模态创作，内置小米 MiMo
系列模型。这是一款闭源商业软件（`unfree`），目前仅支持 `x86_64-linux`。

本包从官方 Linux `.deb` 构建。上游下载页只提供 Windows 与 macOS 安装包链接，
但 Linux 产物实际发布在同一下载 CDN 上，AUR 的
[`mimo-desktop`](https://aur.archlinux.org/packages/mimo-desktop) 包也在跟踪同一产物。
使用该应用需要联网并登录小米 MiMo 账号。

## 维护说明

当前版本：26.909.91205。上游发布新版本后，你可以等待本包更新，或开 Issue 请求更新。

上游发布新版本后，更新 `package.nix` 中的 `version` 和 `hash`。下载直链格式为：

```sh
https://mimocode-cdn.xiaomimimo.com/mimocode/mimodesktop/XiaomiMiMo-<version>-x64.deb
```

获取 SRI 格式 hash：

```sh
nix store prefetch-file https://mimocode-cdn.xiaomimimo.com/mimocode/mimodesktop/XiaomiMiMo-<version>-x64.deb
```

也可以直接运行更新脚本。无参数时会自动检测最新版本，也可以手动指定版本：

```sh
./update.sh
./update.sh <version>
./update.sh -f <version>
```

如果目标版本与 `package.nix` 当前版本相同，脚本会直接退出，不重新计算 hash。使用
`-f` 或 `--force` 时必须提供版本号，并会强制重新计算 hash。

上游没有为 Linux 构建提供 `latest` 别名或更新 feed，因此更新脚本通过 AUR
`mimo-desktop` 包的元数据发现新版本，并校验带版本号的 CDN 直链确实存在后再计算
hash。如果 AUR 包滞后或消失，请手动传入版本号。

## 打包说明

- 上游安装包把应用装在 `/opt/Xiaomi MiMo/`；本包将其重定位到
  `$out/share/xiaomi-mimo-desktop`，并通过 `buildFHSEnv` 以 bubblewrap FHS 沙箱
  运行，启动器名为 `xiaomi-mimo-desktop`。上游 desktop 文件被保留（Exec 改写为
  启动器路径），包括 `xiaomi-mimo://` 协议处理器。
- FHS 沙箱是必需项而非锦上添花：应用自带 CPython 3.12 运行时与一批原生 Node
  模块，其 agent 还会在运行时 `pip install` 第三方 wheel。autoPatchelf 会破坏内置
  运行时的 glibc 符号版本，而运行时安装的 wheel 更无法事后修补，因此整个应用以
  未修补状态在沙箱内按传统发行版的 `/usr/lib` 布局解析依赖。沙箱需要非特权用户
  命名空间（bubblewrap），NixOS 开箱即用。
- 与 NixOS 上其他 Electron 应用一样，上游的 setuid `chrome-sandbox` 无法在 Nix
  store 中生效，启动器会以 `--no-sandbox` 启动应用。
- 电脑控制与自我进化功能使用应用自带的 Python 运行时
  （`resources/runtimes/linux-x64/python/`，由 `resources/computer-use-linux/runtime.py`、
  `resources/evolve-seed/` 驱动），因此不需要系统 Python；这些功能所需的 Python
  依赖由应用在运行时自行安装。
- 唯一已知缺口：内置运行时中 Python 标准库的 `crypt` 模块需要 `libcrypt.so.1`，
  Nixpkgs 与沙箱都提供不了（Nixpkgs 的 libxcrypt 只有带 XCRYPT 符号版本的
  `libcrypt.so.2`）。仅该标准库模块受影响。
- 上游 Linux 构建漏打了小米 passport 登录所需的 `node-machine-id` 包：
  `app.asar/out/main` 里的 `require("node-machine-id")` 必然失败，登录一律报
  "参数错误"（passport 20014）。本包在 `resources/node_modules/node-machine-id`
  放了一个小型替身模块（Node 的模块解析能直接找到它，无需重打 asar）。替身优先
  读真实系统 machine-id（`/var/lib/dbus/machine-id`、`/etc/machine-id`），读不到
  就生成随机 id 并持久化到 `~/.config/Xiaomi MiMo/machine-id`，保证跨启动稳定。
