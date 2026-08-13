# SPDX-License-Identifier: GPL-3.0-or-later
{
  description = "NixOS database host using nixdb";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixdb.url = "github:MrShitFox/nixdb/v0.2.0";
  };

  outputs = { nixpkgs, nixdb, ... }: {
    nixosConfigurations.db-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixdb.nixosModules.default
        ./hardware-configuration.nix
        ./configuration.nix
        ./databases.nix
      ];
    };
  };
}
