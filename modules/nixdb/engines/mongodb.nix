{
  config,
  lib,
  nixdbPackages,
  nixdbVersions,
  pkgs,
  ...
}:

let
  cfg = config.services.nixdb.mongodb;
  mongodb = cfg.instances;
  mongoPkg = cfg.package;
  mongoshPkg = cfg.shellPackage;
  q = lib.escapeShellArg;
  yaml = pkgs.formats.yaml { };
  inherit (import ../../../lib/sizes.nix { inherit lib; }) parseSize;

  mkConfig =
    name: instance:
    yaml.generate "${name}.yaml" {
      storage = {
        dbPath = instance.dataDir;
        wiredTiger.engineConfig.cacheSizeGB = instance.cacheGB;
      };
      net = {
        bindIp = instance.bindAddress;
        port = instance.port;
        unixDomainSocket.enabled = false;
      };
      security.authorization = "enabled";
    };

  mkBootstrapConfig =
    name: instance:
    yaml.generate "${name}-bootstrap.yaml" {
      storage = {
        dbPath = instance.dataDir;
        wiredTiger.engineConfig.cacheSizeGB = instance.cacheGB;
      };
      net = {
        bindIp = "127.0.0.1";
        port = instance.port;
        unixDomainSocket.enabled = false;
      };
      systemLog = {
        destination = "file";
        path = "${instance.dataDir}/bootstrap.log";
        logAppend = true;
      };
      processManagement = {
        fork = true;
        pidFilePath = "/run/${name}/bootstrap.pid";
      };
    };

  mkBootstrapJS =
    name: instance:
    pkgs.writeText "${name}-bootstrap.js" ''
      const admin = db.getSiblingDB("admin");
      const username = ${builtins.toJSON instance.adminUser};
      const password = ${builtins.toJSON instance.password};
      if (admin.getUser(username)) {
        admin.changeUserPassword(username, password);
      } else {
        admin.createUser({
          user: username,
          pwd: password,
          roles: [ { role: "root", db: "admin" } ]
        });
      }
    '';

  mkService =
    name: instance:
    let
      configFile = mkConfig name instance;
      bootstrapConfig = mkBootstrapConfig name instance;
      bootstrapJS = mkBootstrapJS name instance;
      passwordMarker = "${instance.dataDir}/.configured-root-password";
      adminUserMarker = "${instance.dataDir}/.configured-admin-user";
    in
    lib.nameValuePair name {
      description = "MongoDB instance ${name}";
      requires = [ "db-quota-${name}.service" ];
      after = [
        "network.target"
        "db-quota-${name}.service"
      ];
      unitConfig.RequiresMountsFor = instance.dataDir;
      restartTriggers = [
        configFile
        bootstrapConfig
        bootstrapJS
      ];

      preStart = ''
        set -euo pipefail
        ${pkgs.coreutils}/bin/rm -f ${q "${instance.dataDir}/mongod.lock"}

        desired_user=${q instance.adminUser}
        if [ -f ${q adminUserMarker} ]; then
          current_user="$(${pkgs.coreutils}/bin/cat ${q adminUserMarker})"
          if [ "$current_user" != "$desired_user" ]; then
            echo "MongoDB admin user rename for ${name} requires an explicit manual migration" >&2
            exit 1
          fi
        fi

        desired_password=${q instance.password}
        current_password=""
        if [ -f ${q passwordMarker} ]; then
          current_password="$(${pkgs.coreutils}/bin/cat ${q passwordMarker})"
        fi

        if [ "$current_password" != "$desired_password" ]; then
          ${mongoPkg}/bin/mongod --config ${bootstrapConfig}
          ready=0
          for _ in $(${pkgs.coreutils}/bin/seq 1 200); do
            if ${mongoshPkg}/bin/mongosh \
              --quiet --host 127.0.0.1 --port ${toString instance.port} \
              --eval 'db.adminCommand({ ping: 1 }).ok' >/dev/null 2>&1; then
              ready=1
              break
            fi
            ${pkgs.coreutils}/bin/sleep 0.1
          done
          if [ "$ready" -ne 1 ]; then
            echo "MongoDB bootstrap instance ${name} did not become ready" >&2
            exit 1
          fi

          ${mongoshPkg}/bin/mongosh \
            --quiet --host 127.0.0.1 --port ${toString instance.port} \
            --file ${bootstrapJS}
          ${mongoshPkg}/bin/mongosh \
            --quiet --host 127.0.0.1 --port ${toString instance.port} \
            --eval 'db.getSiblingDB("admin").shutdownServer()' >/dev/null 2>&1 || true

          pid_file=${q "/run/${name}/bootstrap.pid"}
          if [ -f "$pid_file" ]; then
            bootstrap_pid="$(${pkgs.coreutils}/bin/cat "$pid_file")"
            for _ in $(${pkgs.coreutils}/bin/seq 1 100); do
              if ! ${pkgs.coreutils}/bin/kill -0 "$bootstrap_pid" 2>/dev/null; then
                break
              fi
              ${pkgs.coreutils}/bin/sleep 0.1
            done
            if ${pkgs.coreutils}/bin/kill -0 "$bootstrap_pid" 2>/dev/null; then
              echo "MongoDB bootstrap instance ${name} did not stop cleanly" >&2
              exit 1
            fi
          fi

          printf '%s' "$desired_password" > ${q passwordMarker}
          ${pkgs.coreutils}/bin/chmod 0600 ${q passwordMarker}
        fi

        printf '%s' "$desired_user" > ${q adminUserMarker}
        ${pkgs.coreutils}/bin/chmod 0600 ${q adminUserMarker}
      '';

      serviceConfig = {
        Type = "simple";
        User = name;
        Group = name;
        RuntimeDirectory = name;
        RuntimeDirectoryMode = "0750";
        ExecStart = "${mongoPkg}/bin/mongod --config ${configFile}";
        Restart = "on-failure";
        RestartSec = "2s";
        Slice = "database.slice";
        CPUWeight = instance.cpuWeight;
        MemoryHigh = instance.memoryHigh;
        MemoryMax = instance.memoryMax;
        MemorySwapMax = instance.memorySwapMax;
        LimitNOFILE = 65536;
        UMask = "0077";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ instance.dataDir ];
      };
    };
in
{
  options.services.nixdb.mongodb = {
    enable = lib.mkEnableOption "MongoDB instances" // {
      default = true;
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = nixdbPackages.mongodb;
      defaultText = lib.literalExpression "nixdb's independently pinned MongoDB package";
    };
    shellPackage = lib.mkOption {
      type = lib.types.package;
      default = nixdbPackages.mongosh;
      defaultText = lib.literalExpression "nixdb's independently pinned mongosh package";
    };
    declaredVersion = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = nixdbVersions.mongodb;
    };
    instances = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            dataDir = lib.mkOption { type = lib.types.strMatching "^/.*"; };
            mountPoint = lib.mkOption { type = lib.types.strMatching "^/.*"; };
            projectId = lib.mkOption { type = lib.types.ints.positive; };
            diskLimit = lib.mkOption { type = lib.types.strMatching "^[0-9]+[KMGTPEkmgtpe]?$"; };
            port = lib.mkOption { type = lib.types.port; };
            bindAddress = lib.mkOption {
              type = lib.types.nonEmptyStr;
              default = "127.0.0.1";
            };
            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
            adminUser = lib.mkOption {
              type = lib.types.addCheck lib.types.nonEmptyStr (value: !lib.hasInfix "\n" value);
            };
            password = lib.mkOption {
              type = lib.types.addCheck lib.types.nonEmptyStr (value: !lib.hasInfix "\n" value);
            };
            cpuWeight = lib.mkOption { type = lib.types.ints.between 1 10000; };
            cacheGB = lib.mkOption { type = lib.types.ints.positive; };
            memoryHigh = lib.mkOption { type = lib.types.strMatching "^[0-9]+[KMGTPEkmgtpe]?$"; };
            memoryMax = lib.mkOption { type = lib.types.strMatching "^[0-9]+[KMGTPEkmgtpe]?$"; };
            memorySwapMax = lib.mkOption {
              type = lib.types.strMatching "^[0-9]+[KMGTPEkmgtpe]?$";
              default = "0";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf (config.services.nixdb.enable && cfg.enable) {
    assertions = [
      {
        assertion = lib.getVersion mongoPkg == cfg.declaredVersion;
        message = "services.nixdb.mongodb: declared version ${cfg.declaredVersion} does not match package ${lib.getVersion mongoPkg}.";
      }
      {
        assertion = lib.all (instance: instance.cacheGB * 1073741824 <= parseSize instance.memoryMax) (
          lib.attrValues mongodb
        );
        message = "services.nixdb.mongodb: WiredTiger cacheGB must not exceed the instance memoryMax.";
      }
    ];

    services.nixdb._internal.instances = lib.mapAttrsToList (name: instance: {
      inherit name;
      kind = "mongodb";
      serviceName = name;
      inherit (instance)
        dataDir
        mountPoint
        projectId
        diskLimit
        cpuWeight
        memoryHigh
        memoryMax
        memorySwapMax
        ;
      ports = [ instance.port ];
      firewallPorts = lib.optional instance.openFirewall instance.port;
      listeners = [
        {
          address = instance.bindAddress;
          port = instance.port;
        }
      ];
      internalCache = {
        kind = "WiredTiger cache";
        value = "${toString instance.cacheGB}G";
      };
    }) mongodb;

    services.nixdb._internal.healthCredentials = lib.mapAttrsToList (name: instance: {
      inherit name;
      engine = "mongodb";
      address = instance.bindAddress;
      username = instance.adminUser;
      inherit (instance) password;
      ports.main = instance.port;
    }) mongodb;

    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "mongodb-ce" ];
    environment.systemPackages = [
      mongoPkg
      mongoshPkg
    ];
    systemd.services = lib.mapAttrs' mkService mongodb;
  };
}
