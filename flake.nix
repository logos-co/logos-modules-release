{
  description = "Logos modules release catalog - CI tooling";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    logos-package = {
      url = "github:logos-co/logos-package";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, logos-package }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        f nixpkgs.legacyPackages.${system} system
      );
    in {
      devShells = forAllSystems (pkgs: system: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            bash
            coreutils
            curl
            findutils
            git
            jq
            python3
            gnutar
            gzip
            cacert
            logos-package.packages.${system}.lgx
          ];
          SSL_CERT_FILE   = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          GIT_SSL_CAINFO  = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        };
      });
    };
}