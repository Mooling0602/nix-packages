# qoder

Qoder IDE — 阿里巴巴推出的 Agentic AI 编程平台。闭源商业软件（`unfree`），目前仅支持 `x86_64-linux`。

## 维护说明

当前版本：1.13.3。上游有更新版本时，可以等待此处更新，或发起 Issue 通知。

上游发布新版本后，更新 `package.nix` 中的 `version` 和 `hash`。下载直链格式为：

```
https://download.qoder.com/release/<version>/qoder_amd64.deb
```

获取 SRI 格式 hash：

```sh
nix store prefetch-file https://download.qoder.com/release/<version>/qoder_amd64.deb

# 或使用 nix-prefetch-url 后转换
nix-prefetch-url https://download.qoder.com/release/<version>/qoder_amd64.deb | xargs nix hash to-sri --type sha256
```

也可以直接运行更新脚本。无参数时会从官方 `latest` Debian 包的 control 元数据自动检测最新版本，也可以手动指定版本：

```sh
./update.sh
./update.sh <version>
./update.sh -f <version>
```

如果目标版本与 `package.nix` 当前版本相同，脚本会直接退出，不重新计算 hash。使用 `-f` 或 `--force` 时必须提供版本号，并会强制重新计算 hash。

## 参考

本包参考了 [boheastill/qoder-nix](https://github.com/boheastill/qoder-nix) 的非官方打包。
