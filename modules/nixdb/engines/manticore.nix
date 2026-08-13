{
  config,
  lib,
  nixdbPackages,
  nixdbVersions,
  pkgs,
  ...
}:

let
  cfg = config.services.nixdb.manticore;
  manticore = cfg.instances;
  manticorePkg = cfg.package;
  q = lib.escapeShellArg;

  sqlString = value: "'${lib.replaceStrings [ "\\" "'" ] [ "\\\\" "''" ] value}'";

  mkConfig =
    name: instance:
    let
      buddyHttpsPort = instance.httpPort + 1;
    in
    pkgs.writeText "${name}.conf" ''
      common {
        plugin_dir = ${instance.dataDir}/plugins
      }

      searchd {
        listen = ${instance.bindAddress}:${toString instance.sqlPort}:mysql
        listen = ${instance.bindAddress}:${toString instance.httpPort}:http
        listen = 127.0.0.1:${toString buddyHttpsPort}:https
        data_dir = ${instance.dataDir}
        pid_file = /run/${name}/searchd.pid
        log = ${instance.dataDir}/searchd.log
        auth = 1
      }
    '';

  mkService =
    name: instance:
    let
      configFile = mkConfig name instance;
      credentialMarker = "${instance.dataDir}/.configured-admin-credentials";
      setPasswordSql = "SET PASSWORD ${sqlString instance.password} FOR ${sqlString instance.adminUser}";
    in
    lib.nameValuePair name {
      description = "Manticore Search instance ${name}";
      requires = [ "db-quota-${name}.service" ];
      after = [
        "network.target"
        "db-quota-${name}.service"
      ];
      unitConfig.RequiresMountsFor = instance.dataDir;
      restartTriggers = [ configFile ];

      preStart = ''
        set -euo pipefail
        ${pkgs.coreutils}/bin/mkdir -p ${q "${instance.dataDir}/plugins"}
      '';

      postStart = ''
        set -euo pipefail

        desired_user=${q instance.adminUser}
        desired_password=${q instance.password}

        probe_desired() {
          ${lib.getExe pkgs.curl} \
            --fail --silent --show-error \
            --user "$desired_user:$desired_password" \
            --data-binary 'SELECT 1' \
            'http://127.0.0.1:${toString instance.httpPort}/sql?mode=raw' \
            >/dev/null
        }

        ready=0
        for _ in $(${pkgs.coreutils}/bin/seq 1 200); do
          http_code="$(${lib.getExe pkgs.curl} \
            --silent --output /dev/null --write-out '%{http_code}' \
            --data-binary 'SELECT 1' \
            'http://127.0.0.1:${toString instance.httpPort}/sql?mode=raw' || true)"
          case "$http_code" in
            200|400|401|403)
              ready=1
              break
              ;;
          esac
          ${pkgs.coreutils}/bin/sleep 0.1
        done
        if [ "$ready" -ne 1 ]; then
          echo "Manticore instance ${name} did not become ready for authentication setup" >&2
          exit 1
        fi

        if ! probe_desired; then
          if [ -f ${q credentialMarker} ]; then
            current_user="$(${pkgs.gnused}/bin/sed -n '1p' ${q credentialMarker})"
            current_password="$(${pkgs.gnused}/bin/sed -n '2p' ${q credentialMarker})"
            if [ "$current_user" != "$desired_user" ]; then
              echo "Manticore admin user rename for ${name} requires an explicit manual migration" >&2
              exit 1
            fi

            ${lib.getExe pkgs.curl} \
              --fail --silent --show-error \
              --user "$current_user:$current_password" \
              --data-binary ${q setPasswordSql} \
              'http://127.0.0.1:${toString instance.httpPort}/sql?mode=raw' \
              > /run/${name}/password-update.json
            ${pkgs.gnugrep}/bin/grep -q '"error":""' /run/${name}/password-update.json
            ${pkgs.coreutils}/bin/rm -f /run/${name}/password-update.json
          else
            printf '%s\n%s\n%s\n' \
              "$desired_user" "$desired_password" "$desired_password" \
              | ${manticorePkg}/bin/searchd \
                  --config ${configFile} --auth-non-interactive
          fi

          if ! probe_desired; then
            echo "Manticore authentication setup failed for ${name}" >&2
            exit 1
          fi
        fi

        printf '%s\n%s\n' "$desired_user" "$desired_password" > ${q credentialMarker}
        ${pkgs.coreutils}/bin/chmod 0600 ${q credentialMarker}
      '';

      serviceConfig = {
        Type = "simple";
        User = name;
        Group = name;
        RuntimeDirectory = name;
        RuntimeDirectoryMode = "0750";
        ExecStart = "${manticorePkg}/bin/searchd --nodetach --config ${configFile}";
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
  options.services.nixdb.manticore = {
    enable = lib.mkEnableOption "Manticore Search instances" // {
      default = true;
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = nixdbPackages.manticore;
      defaultText = lib.literalExpression "nixdb's version-coupled Manticore bundle";
    };
    declaredVersion = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = nixdbVersions.manticore;
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
            sqlPort = lib.mkOption { type = lib.types.port; };
            httpPort = lib.mkOption { type = lib.types.port; };
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
        assertion = lib.getVersion manticorePkg == cfg.declaredVersion;
        message = "services.nixdb.manticore: declared version ${cfg.declaredVersion} does not match package ${lib.getVersion manticorePkg}.";
      }
      {
        assertion = lib.all (instance: instance.httpPort < 65535) (lib.attrValues manticore);
        message = "services.nixdb.manticore: httpPort must leave room for the loopback-only Buddy HTTPS listener on httpPort + 1.";
      }
    ];

    services.nixdb._internal.instances = lib.mapAttrsToList (name: instance: {
      inherit name;
      kind = "manticore";
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
      ports = [
        instance.sqlPort
        instance.httpPort
        (instance.httpPort + 1)
      ];
      firewallPorts = lib.optionals instance.openFirewall [
        instance.sqlPort
        instance.httpPort
      ];
      listeners = [
        {
          address = instance.bindAddress;
          port = instance.sqlPort;
        }
        {
          address = instance.bindAddress;
          port = instance.httpPort;
        }
        {
          address = "127.0.0.1";
          port = instance.httpPort + 1;
        }
      ];
    }) manticore;

    environment.systemPackages = [ manticorePkg ];
    systemd.services = lib.mapAttrs' mkService manticore;
  };
}
