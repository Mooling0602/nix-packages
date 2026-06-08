{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:

{
  qoder = pkgs.callPackage ./pkgs/by-name/qo/qoder/package.nix { };
  reasonix-desktop = pkgs.callPackage ./pkgs/by-name/re/reasonix-desktop/package.nix { };
}
