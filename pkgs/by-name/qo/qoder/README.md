# qoder

Qoder IDE — 阿里巴巴推出的 Agentic AI 编程平台。闭源商业软件（`unfree`），目前仅支持 `x86_64-linux`。

## 维护说明

当前版本：1.6.0。上游有更新版本时，可以等待此处更新，或发起 Issue 通知。

上游发布新版本后，更新 `package.nix` 中的 `version` 和 `hash`。下载直链格式为：

```
https://download.qoder.com/release/{version}/qoder_amd64.deb
```

更新步骤：

```sh
# 获取 SRI 格式 hash
nix store prefetch-file https://download.qoder.com/release/<version>/qoder_amd64.deb

# 或使用 nix-prefetch-url 后转换
nix-prefetch-url https://download.qoder.com/release/<version>/qoder_amd64.deb | xargs nix hash to-sri --type sha256
```

将输出的 SRI hash（`sha256-...` 格式）和 version 同步更新到 `package.nix` 中。

## 参考

本包参考了 [boheastill/qoder-nix](https://github.com/boheastill/qoder-nix) 的非官方打包。
