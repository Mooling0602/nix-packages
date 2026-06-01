{ pkgs ? import <nixpkgs> { } }:

{
  reasonix = pkgs.callPackage ./pkgs/reasonix { };
}
