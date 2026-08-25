# nix-packages

> 中文（简体） · [English](README.md)

Mooling0602 的 [NUR](https://github.com/nix-community/NUR) 软件仓库，由 木泠 维护。未来可能会增加其他软件包。

## 使用方法

### 作为 flake

```nix
{
  inputs.nix-packages.url = "github:Mooling0602/nix-packages";
  # ...
}
```

### 配合 NUR 使用

```nix
{ pkgs, ... }: {
  nixpkgs.overlays = [ (final: prev: {
    qoder = (import (builtins.fetchTarball "https://github.com/Mooling0602/nix-packages/archive/main.tar.gz") { pkgs = final; }).qoder;
  }) ];
}
```

## 软件包列表

| 软件包 | 描述 |
|---------|-------------|
| [`axolotl-launcher-bin`](pkgs/by-name/ax/axolotl-launcher-bin/README.md) | Axolotl Launcher，一款基于 Modrinth 生态构建的自由跨平台 Minecraft 启动器，来自官方 `.deb`（GPL-3.0，仅 x86_64-linux） |
| [`codex-bin`](pkgs/by-name/co/codex-bin/README.md) | OpenAI Codex CLI，来自官方 Linux 二进制发行版（仅 x86_64-linux） |
| [`clawd-on-desk`](pkgs/by-name/cl/clawd-on-desk/README.md) | 桌面伴侣宠物，能实时响应 AI 编程助手会话（仅 x86_64-linux） |
| [`deepseek-harness`](pkgs/by-name/de/deepseek-harness/README.md) | DeepSeek Harness（`dsh`），一个开源的 agent harness 与 CLI，来自官方 npm 发行版 |
| [`openfic`](pkgs/by-name/op/openfic/README.md) | OpenFic，专为小说创作打造的 AI Native 写作工具，来自官方 tar.gz 发布产物（Apache-2.0，仅 x86_64-linux） |
| [`openfic-git`](pkgs/by-name/op/openfic-git/README.md) | OpenFic 桌面端，从上游 `main` 源码构建，使用 nixpkgs Electron，无 FHS 沙箱（Apache-2.0，仅 x86_64-linux，需 nix-ld） |
| [`pebble-mail`](pkgs/by-name/pe/pebble-mail/README.md) | Pebble，一款本地优先的桌面邮件客户端，来自官方 `.deb`（AGPL-3.0，仅 x86_64-linux） |
| [`qoder`](pkgs/by-name/qo/qoder/README.md) | 阿里巴巴的智能 AI 编程平台，具备深度代码库感知（unfree，仅 x86_64-linux） |
| [`reasonix-desktop`](pkgs/by-name/re/reasonix-desktop/README.md) | DeepSeek-Reasonix 推理增强器的桌面应用（仅 x86_64-linux） |

## 许可证

MIT
