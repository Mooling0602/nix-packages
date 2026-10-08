# nix-packages

> English · [简体中文](README_zh_CN.md)

Mooling0602's [NUR](https://github.com/nix-community/NUR) repository. May include other packages in the future.

## Usage

### Add flake inputs

```nix
{
  inputs.nix-packages.url = "github:Mooling0602/nix-packages";
  # ...
}
```

### With NUR Example

```nix
{ pkgs, ... }: {
  nixpkgs.overlays = [ (final: prev: {
    qoder-ide = (import (builtins.fetchTarball "https://github.com/Mooling0602/nix-packages/archive/main.tar.gz") { pkgs = final; }).qoder-ide;
  }) ];
}
```

## Packages

| Package | Description |
|---------|-------------|
| [`axolotl-launcher-bin`](pkgs/by-name/ax/axolotl-launcher-bin/README.md) | Axolotl Launcher, a free cross-platform Minecraft launcher built on the Modrinth ecosystem, from the official `.deb` (GPL-3.0, x86_64-linux only) |
| [`codex-bin`](pkgs/by-name/co/codex-bin/README.md) | OpenAI Codex CLI from the official Linux binary distribution (x86_64-linux only) |
| [`clawd-on-desk`](pkgs/by-name/cl/clawd-on-desk/README.md) | Desktop companion pet that reacts to AI coding assistant sessions in real time (x86_64-linux only) |
| [`deepseek-harness`](pkgs/by-name/de/deepseek-harness/README.md) | DeepSeek Harness (`dsh`), an open-source agent harness and CLI, from the official npm tarball |
| [`deepseek-harness-git`](pkgs/by-name/de/deepseek-harness-git/README.md) | DeepSeek Harness (`dsh`), an open-source agent harness and CLI, from the GitHub source tarball |
| [`deepseek-harness-desktop`](pkgs/by-name/de/deepseek-harness-desktop/README.md) | DeepSeek Harness (`dsh`) as an Electron desktop application, assembled for Linux from the upstream `apps/desktop` build (x86_64-linux only) |
| [`niri-input-portal`](pkgs/by-name/ni/niri-input-portal/README.md) | xdg-desktop-portal InputCapture backend that lets Deskflow-style keyboard/mouse sharing software push this machine's input and clipboard to another computer under niri, built from source with a local patch (MIT, Linux) |
| [`openfic`](pkgs/by-name/op/openfic/README.md) | OpenFic, an AI-native writing tool for fiction authors, from the official tar.gz release (Apache-2.0, x86_64-linux only) |
| [`openfic-git`](pkgs/by-name/op/openfic-git/README.md) | OpenFic desktop built from upstream `main` with nixpkgs Electron, no FHS sandbox (Apache-2.0, x86_64-linux, requires nix-ld) |
| [`pebble-mail`](pkgs/by-name/pe/pebble-mail/README.md) | Pebble, a local-first desktop email client built with Rust, Tauri, and React, from the official `.deb` (AGPL-3.0, x86_64-linux only) |
| [`qoder`](pkgs/by-name/qo/qoder/README.md) | Qoder, an agent workbench for human and AI software teams, from the official `.deb` (unfree, x86_64-linux only) |
| [`qoder-ide`](pkgs/by-name/qo/qoder-ide/README.md) | Qoder IDE, Agentic IDE for Real Software (unfree, x86_64-linux only) |
| [`reasonix-desktop`](pkgs/by-name/re/reasonix-desktop/README.md) | Desktop app for the DeepSeek-Reasonix reasoning enhancer (x86_64-linux only) |
| [`startlive`](pkgs/by-name/st/startlive/README.md) | StartLive, start Bilibili live streams without the official LiveHime client, built from the PyPI source distribution (GPL-3.0, Linux) |
| [`xiaomi-mimo-desktop`](pkgs/by-name/xi/xiaomi-mimo-desktop/README.md) | Xiaomi MiMo Desktop (小米 MiMo 桌面客户端), Xiaomi's official AI desktop agent, from the official Linux `.deb`, run in an FHS sandbox (unfree, x86_64-linux only) |

## License

MIT
