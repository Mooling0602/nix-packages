# nix-packages

> 🇨🇳 简体中文 · [English](README.md)

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
| `[axolotl-launcher-bin](pkgs/by-name/axolotl-launcher-bin/README.md)` | Axolotl Launcher，一款基于 Modrinth 生态构建的自由跨平台 Minecraft 启动器，来自官方 `.deb`（GPL-3.0，仅 x86_64-linux） |
| `[codex-bin](pkgs/by-name/codex-bin/README.md)` | OpenAI Codex CLI，来自官方 Linux 二进制发行版（仅 x86_64-linux） |
| `[clawd-on-desk](pkgs/by-name/clawd-on-desk/README.md)` | 桌面伴侣宠物，能实时响应 AI 编程助手会话（仅 x86_64-linux） |
| `[qoder](pkgs/by-name/qoder/README.md)` | 阿里巴巴的智能 AI 编程平台，具备深度代码库感知（unfree，仅 x86_64-linux） |
| `[reasonix-desktop](pkgs/by-name/reasonix-desktop/README.md)` | DeepSeek-Reasonix 推理增强器的桌面应用（仅 x86_64-linux） |

## 许可证

MIT
