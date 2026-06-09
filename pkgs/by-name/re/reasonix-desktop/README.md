# reasonix-desktop

Reasonix Desktop — DeepSeek-Reasonix 的 Wails/WebKit 桌面应用。

## 维护说明

当前版本：1.4.0。桌面版发布使用 `desktop-v<version>` 标签，Linux 资产名为：

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

桌面版源码构建依赖 Wails、pnpm 和 WebKit/GTK，因此本包使用上游发布的 `x86_64-linux` 预编译二进制。
