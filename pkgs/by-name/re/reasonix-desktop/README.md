# reasonix-desktop

Reasonix Desktop — DeepSeek-Reasonix 的 Wails/WebKit 桌面应用。

## 维护说明

当前版本：1.29.0。桌面版发布使用 `desktop-v<version>` 标签，Linux 资产名为：

```sh
Reasonix-linux-amd64.tar.gz
```

上游发布新版本后，更新 `package.nix` 中的 `version` 和 `hash`。下载直链格式为：

```sh
https://github.com/esengine/DeepSeek-Reasonix/releases/download/desktop-v<version>/Reasonix-linux-amd64.tar.gz
```

获取 SRI 格式 hash：

```sh
nix store prefetch-file https://github.com/esengine/DeepSeek-Reasonix/releases/download/desktop-v<version>/Reasonix-linux-amd64.tar.gz
```

图标 `appIcon` 的 hash 也可能需要同步更新：

```sh
nix store prefetch-file https://raw.githubusercontent.com/esengine/DeepSeek-Reasonix/desktop-v<version>/desktop/build/appicon.png
```

也可以直接运行更新脚本。无参数时会自动检测最新版本，也可以手动指定版本：

```sh
./update.sh
./update.sh <version>
./update.sh -f <version>
```

如果目标版本与 `package.nix` 当前版本相同，脚本会直接退出，不重新计算 hash。使用 `-f` 或 `--force` 时必须提供版本号，并会强制重新计算 hash。

桌面版源码构建依赖 Wails、pnpm 和 WebKit/GTK，因此本包使用上游发布的 `x86_64-linux` 预编译二进制。
