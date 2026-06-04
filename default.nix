{ pkgs ? import <nixpkgs> { } }:

{
  reasonix-go = pkgs.callPackage ./pkgs/reasonix-go { };
  qoder = pkgs.callPackage ./pkgs/qoder { };
}
