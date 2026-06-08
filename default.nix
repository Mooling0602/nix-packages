{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:

{
  reasonix-go = pkgs.callPackage ./pkgs/by-name/re/reasonix-go/package.nix { };
  qoder = pkgs.callPackage ./pkgs/by-name/qo/qoder/package.nix { };
}
