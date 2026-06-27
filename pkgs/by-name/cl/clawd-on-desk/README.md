# clawd-on-desk

Clawd on Desk — 会实时响应 AI 编程助手会话的桌面陪伴宠物。

## 维护说明

当前版本：0.10.0。上游发布新版本后，更新 `package.nix` 中的 `version` 和 `hash`。Linux 资产名为：

```sh
Clawd-on-Desk-<version>-amd64.deb
```

下载直链格式为：

```sh
https://github.com/rullerzhou-afk/clawd-on-desk/releases/download/v<version>/Clawd-on-Desk-<version>-amd64.deb
```

获取 SRI 格式 hash：

```sh
nix store prefetch-file https://github.com/rullerzhou-afk/clawd-on-desk/releases/download/v<version>/Clawd-on-Desk-<version>-amd64.deb
```

也可以直接运行更新脚本：

```sh
./update.sh <version>
```

本包使用上游发布的 `x86_64-linux` 预编译 Debian 包。
