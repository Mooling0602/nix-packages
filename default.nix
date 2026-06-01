{ pkgs ? import <nixpkgs> { } }:

{
  reasonix-go = pkgs.callPackage ./pkgs/reasonix-go { };
}
