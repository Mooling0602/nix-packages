# qoder

> 中文（简体） · [English](README.md)

[Qoder](https://qoder.com/zh/qoder) — 面向人类与 AI 软件团队的智能体工作台。为闭源商业软件（`unfree`），目前仅支持 `x86_64-linux`。

上游已将 Qoder 拆分为多个独立产品：本包只安装独立的 **Qoder 应用**。IDE 由
[`qoder-ide`](../qoder-ide/README_zh_CN.md) 单独打包；独立的 `qoder` CLI 也不在本包内。

## 说明

应用以 `--no-sandbox` 启动。其自带的 Chromium 沙盒辅助程序（`chrome-sandbox`）要求以 root
setuid，而 Nix store 无法提供该权限；仅靠用户命名空间也不足以让它按原样工作。

应用会通过 `electron-updater` 自我更新。这在 Nix store 中无法生效，因此更新走本包。

Electron 的 Wayland 模式相关参数会被应用忽略，并回退回 X11，为避免这种情况，可以添加 `QODER_OZONE_PLATFORM=wayland` 环境变量使软件运行在原生 Wayland 模式下。

## 维护说明

当前版本：0.3.4。上游有更新版本时，可以等待此处更新，或发起 Issue 通知。

上游发布新版本后，更新 `package.nix` 中的 `version` 和 `hash`。下载直链格式为：

```
https://download.qoder.com/qoder-app/releases/<version>/Qoder-linux-amd64.deb
```

注意 Debian 的 `control` 元数据携带 Debian epoch（`Version: 1:0.2.5`），而下载路径与
`package.nix` 使用的是不带 epoch 的 `0.2.5`。

获取 SRI 格式 hash：

```sh
nix store prefetch-file https://download.qoder.com/qoder-app/releases/<version>/Qoder-linux-amd64.deb

# 或使用 nix-prefetch-url 后转换
nix-prefetch-url https://download.qoder.com/qoder-app/releases/<version>/Qoder-linux-amd64.deb | nix hash to-sri --type sha256
```

也可以直接运行更新脚本。无参数时会交叉校验两个来源并取较新的版本：更新日志页面
（[qoder.com/zh/changelog?type=app](https://qoder.com/zh/changelog?type=app)，其内嵌 JSON 列出了
所有发布版本）与官方 `qoder-app/releases/latest/Qoder-linux-amd64.deb` 的 `control` 元数据。
之所以两者都查，是因为下载用的 `latest` 别名可能滞后，否则脚本会对过期版本报出「已是最新」。
也可以手动指定版本：

```sh
./update.sh
./update.sh <version>
./update.sh -f <version>
```

如果目标版本与 `package.nix` 当前版本相同，脚本会直接退出，不重新计算 hash。使用 `-f` 或
`--force` 时必须提供版本号，并会强制重新计算 hash。
