# clawd-on-desk

Clawd on Desk — 会实时响应 AI 编程助手会话的桌面陪伴宠物。

## 维护说明

当前版本：0.14.0。上游发布新版本后，更新 `package.nix` 中的 `version` 和 `hash`。Linux 资产名为：

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

也可以直接运行更新脚本。无参数时会自动检测最新版本，也可以手动指定版本：

```sh
./update.sh
./update.sh <version>
./update.sh -f <version>
```

如果目标版本与 `package.nix` 当前版本相同，脚本会直接退出，不重新计算 hash。使用 `-f` 或 `--force` 时必须提供版本号，并会强制重新计算 hash。

本包使用上游发布的 `x86_64-linux` 预编译 Debian 包。
