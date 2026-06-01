{
  description = "Mooling's NUR packages";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: let
    forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.platforms.unix;
  in {
    packages = forAllSystems (system: import self { pkgs = nixpkgs.legacyPackages.${system}; });

    legacyPackages = forAllSystems (system: import self { pkgs = import nixpkgs { inherit system; }; });
  };
}
