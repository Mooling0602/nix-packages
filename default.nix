{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:

{
  codex-bin = pkgs.callPackage ./pkgs/by-name/co/codex-bin/package.nix { };
  axolotl-launcher-bin = pkgs.callPackage ./pkgs/by-name/ax/axolotl-launcher-bin/package.nix { };
  deepseek-harness = pkgs.callPackage ./pkgs/by-name/de/deepseek-harness/package.nix { };
  qoder = pkgs.callPackage ./pkgs/by-name/qo/qoder/package.nix { };
  reasonix-desktop = pkgs.callPackage ./pkgs/by-name/re/reasonix-desktop/package.nix { };
  clawd-on-desk = pkgs.callPackage ./pkgs/by-name/cl/clawd-on-desk/package.nix { };
  pebble-mail = pkgs.callPackage ./pkgs/by-name/pe/pebble-mail/package.nix { };
  openfic = pkgs.callPackage ./pkgs/by-name/op/openfic/package.nix { };
  openfic-git = pkgs.callPackage ./pkgs/by-name/op/openfic-git/package.nix { };
}
