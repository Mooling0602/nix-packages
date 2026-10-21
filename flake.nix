{
  description = "Mooling's NUR packages";

  inputs = {
    # zstd flavored nixexprs tarball, ~10x faster to decompress than .tar.xz.
    # The .tar.xz flavor is discontinued after 2027-12-31.
    # https://github.com/NixOS/nixpkgs/pull/535272
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
    importPnpmLock = {
      url = "git+https://tangled.org/scrumplex.net/importPnpmLock.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, importPnpmLock }: let
    forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.platforms.unix;
    pkgsFor = system: import nixpkgs { 
      inherit system; 
      config.allowUnfree = true;
      overlays = [ importPnpmLock.overlays.default ];
    };
  in {
    packages = forAllSystems (system: import self { pkgs = pkgsFor system; });

    legacyPackages = forAllSystems (system: import self { pkgs = pkgsFor system; });
  };
}
