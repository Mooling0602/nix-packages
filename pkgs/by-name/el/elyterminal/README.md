# ELYTerminal

[简体中文](README_zh_CN.md)

[ELYTerminal](https://github.com/ELY-Open-Source/ELYTerminal) is a GPU-rendered terminal built with GPUI and Ely. This package repackages the official Linux x86_64 `.deb` release, including its desktop entry, icon, and manual page.

Current version: 0.2.4.

```sh
nix run github:Mooling0602/nix-packages#elyterminal
```

The package supports `x86_64-linux` only. A working graphics stack and Vulkan driver are required.

## Update

```bash
./update.sh
```

To update to a specific version:

```bash
./update.sh 0.2.4
```
