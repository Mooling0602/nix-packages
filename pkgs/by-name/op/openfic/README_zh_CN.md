# openfic

> 中文（简体） · [English](README.md)

[OpenFic](https://github.com/syrizelink/OpenFic) — 专为小说创作打造的跨平台、用户友好、AI Native 的一站式写作工具。开源软件（Apache-2.0），使用上游发布的 `x86_64-linux` 预编译产物打包。

## 为什么用 FHS 包装？

Linux 桌面端是 electron-builder 分发产物，但 Python 后端**并未**内置于压缩包中：首次启动时应用会从 GitHub 下载
[python-build-standalone](https://github.com/astral-sh/python-build-standalone)
的 CPython，并从 PyPI 安装 `openfic` 后端到其数据目录下的 venv 中。这些运行时下载的 ELF 二进制依赖 FHS 目录布局
（`/lib64/ld-linux-x86-64.so.2`），在 NixOS 上并不存在，因此本包使用 bubblewrap FHS 环境（`buildFHSEnv`）包装，让整套运行时开箱即用。

FHS 方案的副作用：

- Chromium 的 setuid 沙箱不可用，应用以 `--no-sandbox` 启动。
- 首次启动需要联网（GitHub + PyPI）来安装后端运行时。

## 维护说明

当前版本：0.11.0。上游发布使用 `v<version>` 标签，Linux x86_64 产物命名为：

```sh
OpenFic-<version>-linux-x86_64.tar.gz
```

上游发布新版本后，更新 `package.nix` 中的 `version` 和 `hash`。下载直链格式为：

```sh
https://github.com/syrizelink/OpenFic/releases/download/v<version>/OpenFic-<version>-linux-x86_64.tar.gz
```

获取 SRI 格式 hash：

```sh
nix store prefetch-file https://github.com/syrizelink/OpenFic/releases/download/v<version>/OpenFic-<version>-linux-x86_64.tar.gz
```

也可以直接运行更新脚本。无参数时会通过 GitHub API 自动检测最新版本，也可以手动指定版本：

```sh
./update.sh
./update.sh <version>
./update.sh -f <version>
```

如果目标版本与 `package.nix` 当前版本相同，脚本会直接退出，不重新计算 hash。使用 `-f` 或 `--force` 时必须提供版本号，并会强制重新计算 hash。
