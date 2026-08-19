# nix-packages

> English · [简体中文](README_zh_CN.md)

Mooling0602's [NUR](https://github.com/nix-community/NUR) repository. May include other packages in the future.

## Usage

### As a flake

```nix
{
  inputs.nix-packages.url = "github:Mooling0602/nix-packages";
  # ...
}
```

### With NUR

```nix
{ pkgs, ... }: {
  nixpkgs.overlays = [ (final: prev: {
    qoder = (import (builtins.fetchTarball "https://github.com/Mooling0602/nix-packages/archive/main.tar.gz") { pkgs = final; }).qoder;
  }) ];
}
```

## Packages

| Package | Description |
|---------|-------------|
| `[axolotl-launcher-bin](pkgs/by-name/ax/axolotl-launcher-bin/README.md)` | Axolotl Launcher, a free cross-platform Minecraft launcher built on the Modrinth ecosystem, from the official `.deb` (GPL-3.0, x86_64-linux only) |
| `[codex-bin](pkgs/by-name/codex-bin/co/README.md)` | OpenAI Codex CLI from the official Linux binary distribution (x86_64-linux only) |
| `[clawd-on-desk](pkgs/by-name/cl/clawd-on-desk/README.md)` | Desktop companion pet that reacts to AI coding assistant sessions in real time (x86_64-linux only) |
| `[qoder](pkgs/by-name/qo/qoder/README.md)` | Alibaba's agentic AI coding platform with deep codebase awareness (unfree, x86_64-linux only) |
| `[reasonix-desktop](pkgs/by-name/re/reasonix-desktop/README.md)` | Desktop app for the DeepSeek-Reasonix reasoning enhancer (x86_64-linux only) |

## License

MIT
