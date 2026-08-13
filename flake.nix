# SPDX-License-Identifier: GPL-3.0-or-later
{
  description = "nixdb: modular NixOS database stack and operator CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/fcb8fcd6bf2d0adecae5bd491afaaaf8311b758d";
    mongodb-nixpkgs.url = "github:NixOS/nixpkgs/fcb8fcd6bf2d0adecae5bd491afaaaf8311b758d";
    mysql-nixpkgs.url = "github:NixOS/nixpkgs/fcb8fcd6bf2d0adecae5bd491afaaaf8311b758d";
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      versions = import ./versions;
      release = {
        version = "0.2.0";
        revision = self.rev or self.dirtyRev or "unknown";
      };

      mkPackageSet =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          mongodbPkgs = import inputs.mongodb-nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "mongodb-ce" ];
          };
          mysqlPkgs = import inputs.mysql-nixpkgs { inherit system; };
          manticore = pkgs.callPackage ./packages/manticore { };
          components = manticore.componentVersions;
          declaredComponents = {
            search = versions.manticore;
            buddy = versions.manticoreBuddy;
            columnar = versions.manticoreColumnar;
            secondary = versions.manticoreSecondary;
            knn = versions.manticoreKnn;
            embeddings = versions.manticoreEmbeddings;
            executor = versions.manticoreExecutor;
            backup = versions.manticoreBackup;
            load = versions.manticoreLoad;
            tzdata = versions.manticoreTzdata;
            galera = versions.manticoreGalera;
          };
          mismatches = nixpkgs.lib.filter (name: declaredComponents.${name} != components.${name}) (
            builtins.attrNames declaredComponents
          );
        in
        assert nixpkgs.lib.assertMsg (mismatches == [ ])
          "Manticore component declarations disagree with the packaged bundle: ${builtins.concatStringsSep ", " mismatches}";
        {
          mongodb = mongodbPkgs.mongodb-ce;
          mongosh = mongodbPkgs.mongosh;
          mysql = mysqlPkgs.mysql84;
          inherit manticore;
        };

      nixdbModule =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          dbPackages = mkPackageSet pkgs.stdenv.hostPlatform.system;
          nixdbCli = pkgs.callPackage ./packages/nixdb-cli { inherit dbPackages; };
        in
        {
          imports = [ ./modules/nixdb ];
          _module.args = {
            nixdbPackages = dbPackages;
            nixdbVersions = versions;
            nixdbRelease = release;
            inherit nixdbCli;
          };
        };

      evalSystem = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nixdbModule
          ./tests/eval-host.nix
        ];
      };
      evaluatedInstances = evalSystem.config.services.nixdb._internal.instances;
    in
    {
      nixosModules = {
        default = nixdbModule;
        nixdb = nixdbModule;
      };

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          dbPackages = mkPackageSet system;
        in
        dbPackages
        // {
          default = pkgs.callPackage ./packages/nixdb-cli { inherit dbPackages; };
          nixdb-cli = pkgs.callPackage ./packages/nixdb-cli { inherit dbPackages; };
          manticoreDeployed = dbPackages.manticore;
        }
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          module-evaluation =
            pkgs.runCommand "nixdb-module-evaluation"
              {
                evaluated = builtins.toJSON evaluatedInstances;
              }
              ''
                test ${toString (builtins.length evaluatedInstances)} -eq 3
                test -n "$evaluated"
                touch "$out"
              '';
          secret-sanity =
            pkgs.runCommand "nixdb-secret-sanity"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.findutils
                  pkgs.gnugrep
                ];
              }
              ''
                bash ${./tests/no-secrets.sh} ${self}
                touch "$out"
              '';
        }
      );

      templates = {
        default = self.templates.single-host;
        single-host = {
          path = ./templates/single-host;
          description = "A downstream NixOS host that consumes nixdb";
        };
      };
    };
}
