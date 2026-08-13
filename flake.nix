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
          nixdbCli = pkgs.callPackage ./packages/nixdb-cli { };
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
          default = pkgs.callPackage ./packages/nixdb-cli { };
          nixdb-cli = pkgs.callPackage ./packages/nixdb-cli { };
          manticoreDeployed = dbPackages.manticore;
          vm-integration-test = import ./tests/vm-integration.nix {
            inherit pkgs nixdbModule;
          };
        }
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          module-evaluation = import ./tests/module-evaluation.nix {
            inherit nixpkgs pkgs nixdbModule;
          };
          cli-tests =
            pkgs.runCommand "nixdb-cli-tests"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.git
                  pkgs.hostname
                  pkgs.jq
                  pkgs.util-linux
                ];
              }
              ''
                bash ${./tests/cli.sh} ${self}
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
          shellcheck =
            pkgs.runCommand "nixdb-shellcheck"
              {
                nativeBuildInputs = [ pkgs.shellcheck ];
              }
              ''
                shellcheck \
                  ${./packages/nixdb-cli/nixdb} \
                  ${./tests/no-secrets.sh} \
                  ${./scripts/check-health} \
                  ${./scripts/check-quotas} \
                  ${./scripts/check-resources} \
                  ${./scripts/check-versions}
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
