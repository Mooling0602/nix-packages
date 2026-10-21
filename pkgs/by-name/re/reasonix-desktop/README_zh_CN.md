# reasonix-desktop

> 中文（简体） · [English](README.md)

[Reasonix](https://github.com/esengine/DeepSeek-Reasonix) Desktop —— DeepSeek-Reasonix 的 Electron 桌面应用。

## 维护说明

当前版本：1.39.10。Linux 资产发布在 `desktop-v<version>` 标签下，资产名为：

```sh
Reasonix-linux-amd64.tar.gz
```

### 上游有多个互相独立的发布分支

DeepSeek-Reasonix 在同一个仓库里发布多个产品，各自使用独立的标签命名空间：

| 标签命名空间 | 对应产品 |
| --- | --- |
| `desktop-v*` | 本包（1.x Electron 桌面版） |
| `studio-v*` | Reasonix Studio |
| `v*` | 2.x 命令行版本 |
| `npm-v*`、`dsnix-v*` | 其他打包分支 |

因此 GitHub 的“最新发布”（`/releases/latest`，以及 releases 页面上的 `latest` 跳转）**并不能**指出最新的桌面版——它只会返回最近发布的那条分支。所以 `update.sh` 改为从标签命名空间里发现版本，完全不再询问 API 的 latest。

本包只跟踪 `desktop-v*`。Studio 是上游的另一个产品，应当另建一个包，而不是并到这里——即使桌面版这条线不再是最活跃的那条也是如此。

### 更新

```sh
./update.sh          # 自动探测最新的、且确实有资产的桌面版
./update.sh <version>   # 指定版本
./update.sh -f <version>  # 强制：即使版本未变也重新计算 hash
```

无参数时，脚本用 `git ls-remote` 列出 `refs/tags/desktop-v*`，按版本排序，再从新到旧逐个检查该标签是否真的发布了 `Reasonix-linux-amd64.tar.gz`，最多跳过 10 个候选。这一点是必要的：有些 `desktop-v*` 标签并没有对应的 release（例如 `1.38.4`）。如果目标版本与 `package.nix` 中的当前版本相同，脚本会直接退出，不重新计算任何东西。

手动更新时：

```sh
nix store prefetch-file https://github.com/esengine/DeepSeek-Reasonix/releases/download/desktop-v<version>/Reasonix-linux-amd64.tar.gz
```

图标 `appIcon` 的 hash 也可能需要同步更新：

```sh
nix store prefetch-file https://raw.githubusercontent.com/esengine/DeepSeek-Reasonix/desktop-v<version>/desktop/build/appicon.png
```

### 打包结构

在 `desktop-v1.38.3` 及之前，压缩包是单个自包含的 Wails/WebKit 二进制，只装一个文件就够了。从 `desktop-v1.39.0` 起改为 Electron 负载：`reasonix-desktop` 只是一个小启动器，它会加载同级 `app/` 目录中的外壳，同时还有 `reasonix`、`reasonix-guard`、`reasonix-launcher`。因此整棵目录树一起安装到 `$out/lib/reasonix-desktop`，再由 `$out/bin/reasonix-desktop` 链接进去——只复制启动器会得到一个拒绝启动的应用。

桌面版本从源码构建仍需要 pnpm 以及完整的 Electron/WebKit 工具链，因此本包使用上游发布的 `x86_64-linux` 预编译压缩包。
