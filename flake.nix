{
  description = "Mooling's NUR packages";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: let
    forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.platforms.unix;
    pkgsFor = system: import nixpkgs { inherit system; config.allowUnfree = true; };
  in {
    packages = forAllSystems (system: import self { pkgs = pkgsFor system; });

    legacyPackages = forAllSystems (system: import self { pkgs = pkgsFor system; });
  };
}
