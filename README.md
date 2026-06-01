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
    reasonix = (import (builtins.fetchTarball "https://github.com/Mooling0602/nix-packages/archive/main.tar.gz") { pkgs = final; }).reasonix;
  }) ];
}
```

## Packages

| Package | Description |
|---------|-------------|
| `reasonix` | DeepSeek-native AI coding agent with TUI, MCP, and Wails desktop support |

## License

MIT
