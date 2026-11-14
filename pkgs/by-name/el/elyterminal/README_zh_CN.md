# ELYTerminal

[English](README.md)

[ELYTerminal](https://github.com/ELY-Open-Source/ELYTerminal) 是一款基于 GPUI 和 Ely、使用 GPU 渲染的终端。本包重新打包上游官方 Linux x86_64 `.deb`，包含桌面启动项、图标和手册页。

当前版本：0.2.4。

```sh
nix run github:Mooling0602/nix-packages#elyterminal
```

本包仅支持 `x86_64-linux`，需要可用的图形环境和 Vulkan 驱动。

## 更新

```bash
./update.sh
```

更新到指定版本：

```bash
./update.sh 0.2.4
```
