# nix-packages

Mooling0602's [NUR](https://github.com/nix-community/NUR) repository — maintained by 木泠. May include other packages in the future.

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
| `codex-bin` | OpenAI Codex CLI from the official Linux binary distribution (x86_64-linux only) |
| `clawd-on-desk` | Desktop companion pet that reacts to AI coding assistant sessions in real time (x86_64-linux only) |
| `qoder` | Alibaba's agentic AI coding platform with deep codebase awareness (unfree, x86_64-linux only) |
| `reasonix-desktop` | Desktop app for the DeepSeek-Reasonix reasoning enhancer (x86_64-linux only) |

## License

MIT
