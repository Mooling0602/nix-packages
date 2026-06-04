{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:

{
  reasonix-go = pkgs.callPackage ./pkgs/reasonix-go { };
  qoder = pkgs.callPackage ./pkgs/qoder { };
}
