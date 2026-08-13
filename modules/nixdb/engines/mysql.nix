{
  config,
  lib,
  nixdbPackages,
  nixdbVersions,
  pkgs,
  ...
}:

let
  cfg = config.services.nixdb.mysql;
  mysql = cfg.instances;
  mysqlPkg = cfg.package;
  q = lib.escapeShellArg;
  ini = pkgs.formats.ini { listsAsDuplicateKeys = true; };
  inherit (import ../../../lib/sizes.nix { inherit lib; }) parseSize;

  sqlString = value: "'${lib.replaceStrings [ "\\" "'" ] [ "\\\\" "''" ] value}'";

  mkConfig =
    name: instance:
    ini.generate "${name}.cnf" {
      client = {
        port = instance.port;
        socket = "/run/${name}/mysqld.sock";
      };
      mysqld = {
        datadir = instance.dataDir;
        bind_address = instance.bindAddress;
        port = instance.port;
        socket = "/run/${name}/mysqld.sock";
        pid_file = "/run/${name}/mysqld.pid";
        mysqlx = "OFF";
        skip_name_resolve = true;
        default_storage_engine = "InnoDB";
        innodb_buffer_pool_size = instance.bufferPool;
        max_connections = instance.maxConnections;
        plugin-load-add = [ "auth_socket.so" ];
      };
    };

  mkService =
    name: instance:
    let
      configFile = mkConfig name instance;
      socket = "/run/${name}/mysqld.sock";
      maintenanceUser = sqlString name;
      adminUser = sqlString instance.adminUser;
      adminPassword = sqlString instance.password;
      firstInitMarker = "${instance.dataDir}/.mysql-first-init";
      adminUserMarker = "${instance.dataDir}/.configured-admin-user";
    in
    lib.nameValuePair name {
      description = "MySQL instance ${name}";
      requires = [ "db-quota-${name}.service" ];
      after = [
        "network.target"
        "db-quota-${name}.service"
      ];
      unitConfig.RequiresMountsFor = instance.dataDir;
      restartTriggers = [ configFile ];
      path = [ pkgs.hostname-debian ];

      preStart = ''
        set -euo pipefail
        desired_user=${q instance.adminUser}
        if [ -f ${q adminUserMarker} ]; then
          current_user="$(${pkgs.coreutils}/bin/cat ${q adminUserMarker})"
          if [ "$current_user" != "$desired_user" ]; then
            echo "MySQL admin user rename for ${name} requires an explicit manual migration" >&2
            exit 1
          fi
        fi

        if [ ! -d ${q "${instance.dataDir}/mysql"} ]; then
          ${mysqlPkg}/bin/mysqld \
            --defaults-file=${configFile} \
            --user=${q name} \
            --datadir=${q instance.dataDir} \
            --basedir=${mysqlPkg} \
            --initialize-insecure
          ${pkgs.coreutils}/bin/touch ${q firstInitMarker}
        fi
      '';

      postStart = ''
                set -euo pipefail
                if [ -f ${q firstInitMarker} ]; then
                  ${mysqlPkg}/bin/mysql \
                    --protocol=SOCKET --socket=${q socket} -uroot <<'SQL'
        CREATE USER IF NOT EXISTS ${maintenanceUser}@'localhost'
          IDENTIFIED WITH auth_socket;
        GRANT ALL PRIVILEGES ON *.*
          TO ${maintenanceUser}@'localhost' WITH GRANT OPTION;
        ALTER USER 'root'@'localhost' IDENTIFIED WITH auth_socket;
        FLUSH PRIVILEGES;
        SQL
                  ${pkgs.coreutils}/bin/rm -f ${q firstInitMarker}
                fi

                ${mysqlPkg}/bin/mysql \
                  --protocol=SOCKET --socket=${q socket} -u ${q name} <<'SQL'
        CREATE USER IF NOT EXISTS ${adminUser}@'%' IDENTIFIED BY ${adminPassword};
        ALTER USER ${adminUser}@'%' IDENTIFIED BY ${adminPassword};
        GRANT ALL PRIVILEGES ON *.* TO ${adminUser}@'%' WITH GRANT OPTION;
        FLUSH PRIVILEGES;
        SQL

                printf '%s' ${q instance.adminUser} > ${q adminUserMarker}
                ${pkgs.coreutils}/bin/chmod 0600 ${q adminUserMarker}
      '';

      serviceConfig = {
        Type = "notify";
        User = name;
        Group = name;
        RuntimeDirectory = name;
        RuntimeDirectoryMode = "0750";
        ExecStart =
          "${mysqlPkg}/bin/mysqld"
          + " --defaults-file=${configFile}"
          + " --user=${name}"
          + " --datadir=${instance.dataDir}"
          + " --basedir=${mysqlPkg}";
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
  options.services.nixdb.mysql = {
    enable = lib.mkEnableOption "MySQL instances" // {
      default = true;
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = nixdbPackages.mysql;
      defaultText = lib.literalExpression "nixdb's independently pinned MySQL package";
    };
    declaredVersion = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = nixdbVersions.mysql;
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
            bufferPool = lib.mkOption { type = lib.types.strMatching "^[0-9]+[KMGTPEkmgtpe]?$"; };
            maxConnections = lib.mkOption { type = lib.types.ints.positive; };
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
        assertion = lib.getVersion mysqlPkg == cfg.declaredVersion;
        message = "services.nixdb.mysql: declared version ${cfg.declaredVersion} does not match package ${lib.getVersion mysqlPkg}.";
      }
      {
        assertion = lib.all (instance: parseSize instance.bufferPool <= parseSize instance.memoryMax) (
          lib.attrValues mysql
        );
        message = "services.nixdb.mysql: InnoDB bufferPool must not exceed the instance memoryMax.";
      }
    ];

    services.nixdb._internal.instances = lib.mapAttrsToList (name: instance: {
      inherit name;
      kind = "mysql";
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
        kind = "InnoDB buffer pool";
        value = instance.bufferPool;
      };
      engineMetadata.maxConnections = instance.maxConnections;
    }) mysql;

    services.nixdb._internal.healthCredentials = lib.mapAttrsToList (name: instance: {
      inherit name;
      engine = "mysql";
      address = instance.bindAddress;
      username = instance.adminUser;
      inherit (instance) password;
      ports.main = instance.port;
    }) mysql;

    environment.systemPackages = [ mysqlPkg ];
    systemd.services = lib.mapAttrs' mkService mysql;
  };
}
