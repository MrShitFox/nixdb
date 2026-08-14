# SPDX-License-Identifier: GPL-3.0-or-later
{
  config,
  lib,
  nixdbPackages,
  nixdbVersions,
  pkgs,
  ...
}:

let
  cfg = config.services.nixdb.redis;
  instances = cfg.instances;
  redisPkg = cfg.package;
  q = lib.escapeShellArg;
  inherit (import ../../../lib/sizes.nix { inherit lib; }) parseSize;

  sizeType = lib.types.strMatching "^[0-9]+[KMGTPEkmgtpe]?$";
  noNewline = value: !lib.hasInfix "\n" value && !lib.hasInfix "\r" value;
  token = value: builtins.match "^[^[:space:]]+$" value != null;
  safeUser = value: builtins.match "^[A-Za-z0-9_-]+$" value != null;
  redisBool = value: if value then "yes" else "no";
  redisValue =
    value:
    if builtins.isBool value then
      redisBool value
    else if builtins.isInt value then
      toString value
    else
      value;
  asList = value: if builtins.isList value then value else [ value ];
  rawLineName =
    line:
    let
      match = builtins.match "^[[:space:]]*([A-Za-z0-9_-]+)[[:space:]].*$" line;
    in
    if match == null then null else builtins.elemAt match 0;

  typedDirectiveNames = [
    "daemonize"
    "supervised"
    "pidfile"
    "logfile"
    "dir"
    "dbfilename"
    "appenddirname"
    "port"
    "tls-port"
    "bind"
    "protected-mode"
    "tcp-backlog"
    "timeout"
    "tcp-keepalive"
    "databases"
    "unixsocket"
    "unixsocketperm"
    "maxmemory"
    "maxmemory-policy"
    "maxmemory-samples"
    "appendonly"
    "appendfsync"
    "no-appendfsync-on-rewrite"
    "auto-aof-rewrite-percentage"
    "auto-aof-rewrite-min-size"
    "aof-use-rdb-preamble"
    "aof-load-truncated"
    "save"
    "rdbcompression"
    "rdbchecksum"
    "aclfile"
    "tls-cert-file"
    "tls-key-file"
    "tls-ca-cert-file"
    "tls-auth-clients"
    "io-threads"
    "io-threads-do-reads"
    "hz"
    "dynamic-hz"
    "activerehashing"
    "lazyfree-lazy-eviction"
    "lazyfree-lazy-expire"
    "lazyfree-lazy-server-del"
    "replica-lazy-flush"
    "activedefrag"
    "active-defrag-ignore-bytes"
    "active-defrag-threshold-lower"
    "active-defrag-threshold-upper"
    "active-defrag-cycle-min"
    "active-defrag-cycle-max"
    "client-output-buffer-limit"
    "slowlog-log-slower-than"
    "slowlog-max-len"
    "latency-monitor-threshold"
  ];

  rawNames =
    instance:
    (builtins.attrNames instance.extraConfig)
    ++ lib.filter (name: name != null) (map rawLineName instance.extraConfigLines);
  rawValuesSafe =
    instance:
    lib.all noNewline instance.extraConfigLines
    && lib.all (name: builtins.match "^[A-Za-z0-9_-]+$" name != null) (
      builtins.attrNames instance.extraConfig
    )
    && lib.all (
      value: lib.all (item: if builtins.isString item then noNewline item else true) (asList value)
    ) (builtins.attrValues instance.extraConfig);
  rawNoCollision = instance: lib.intersectLists typedDirectiveNames (rawNames instance) == [ ];
  persistenceMode =
    instance:
    if instance.persistence.appendOnly && instance.persistence.saveRules != [ ] then
      "AOF+RDB"
    else if instance.persistence.appendOnly then
      "AOF"
    else if instance.persistence.saveRules != [ ] then
      "RDB"
    else
      "none";
  configLine = name: value: "${name} ${redisValue value}";
  renderExtra =
    instance:
    lib.concatStringsSep "\n" (
      (lib.concatMap (name: map (value: configLine name value) (asList instance.extraConfig.${name})) (
        builtins.attrNames instance.extraConfig
      ))
      ++ instance.extraConfigLines
    );
  renderAclUser =
    name: user:
    lib.concatStringsSep " " (
      [
        "user"
        name
        (if user.enable then "on" else "off")
        (if user.password == null then "nopass" else ">${user.password}")
      ]
      ++ user.commands
      ++ user.keys
      ++ user.channels
    );
  mkAclFile =
    name: instance:
    pkgs.writeText "${name}.acl" (
      lib.concatStringsSep "\n" (
        [
          (renderAclUser "default" instance.authentication.defaultUser)
          (renderAclUser instance.authentication.adminUser {
            enable = true;
            password = instance.authentication.password;
            commands = [ "+@all" ];
            keys = [ "~*" ];
            channels = [ "&*" ];
          })
        ]
        ++ lib.mapAttrsToList renderAclUser instance.authentication.users
      )
      + "\n"
    );
  moduleLines = lib.concatMapStringsSep "\n" (
    module: "loadmodule ${redisPkg}/lib/redis/modules/${module}.so"
  ) redisPkg.bundledModules;
  mkConfig =
    name: instance:
    let
      aclFile = mkAclFile name instance;
      tls = instance.tls;
      persistence = instance.persistence;
      buffers = instance.clientOutputBufferLimits;
      extra = renderExtra instance;
      saveLines =
        if persistence.saveRules == [ ] then
          [ "save \"\"" ]
        else
          map (rule: "save ${toString rule.seconds} ${toString rule.changes}") persistence.saveRules;
    in
    pkgs.writeText "${name}.redis.conf" ''
      daemonize no
      supervised systemd
      pidfile /run/${name}/redis.pid
      logfile ""

      bind ${lib.concatStringsSep " " instance.bind}
      port ${if instance.port == null then "0" else toString instance.port}
      tls-port ${if tls.enable then toString tls.port else "0"}
      protected-mode ${redisBool instance.protectedMode}
      tcp-backlog ${toString instance.tcpBacklog}
      timeout ${toString instance.timeout}
      tcp-keepalive ${toString instance.tcpKeepalive}
      databases ${toString instance.databases}
      ${lib.optionalString (instance.unixSocket != null) "unixsocket ${instance.unixSocket}"}
      ${lib.optionalString (instance.unixSocket != null) "unixsocketperm ${instance.unixSocketPerm}"}

      ${lib.optionalString tls.enable ''
        tls-cert-file ${tls.certFile}
        tls-key-file ${tls.keyFile}
        tls-ca-cert-file ${tls.caFile}
        tls-auth-clients ${redisBool tls.authClients}
      ''}

      dir ${instance.dataDir}
      dbfilename ${persistence.dbFilename}
      rdbcompression ${redisBool persistence.rdbCompression}
      rdbchecksum ${redisBool persistence.rdbChecksum}
      ${lib.concatStringsSep "\n" saveLines}

      appendonly ${redisBool persistence.appendOnly}
      appendfsync ${persistence.appendFsync}
      no-appendfsync-on-rewrite ${redisBool persistence.noAppendfsyncOnRewrite}
      auto-aof-rewrite-percentage ${toString persistence.autoAofRewritePercentage}
      auto-aof-rewrite-min-size ${persistence.autoAofRewriteMinSize}
      appenddirname ${persistence.appendDirName}
      aof-use-rdb-preamble ${redisBool persistence.aofUseRdbPreamble}
      aof-load-truncated ${redisBool persistence.aofLoadTruncated}

      maxmemory ${instance.maxMemory}
      maxmemory-policy ${instance.maxMemoryPolicy}
      maxmemory-samples ${toString instance.maxMemorySamples}

      io-threads ${toString instance.ioThreads}
      io-threads-do-reads ${redisBool instance.ioThreadsDoReads}
      hz ${toString instance.hz}
      dynamic-hz ${redisBool instance.dynamicHz}
      activerehashing ${redisBool instance.activeRehashing}
      lazyfree-lazy-eviction ${redisBool instance.lazyfree.lazyEviction}
      lazyfree-lazy-expire ${redisBool instance.lazyfree.lazyExpire}
      lazyfree-lazy-server-del ${redisBool instance.lazyfree.lazyServerDel}
      replica-lazy-flush ${redisBool instance.lazyfree.replicaLazyFlush}
      activedefrag ${redisBool instance.activeDefrag.enable}
      active-defrag-ignore-bytes ${instance.activeDefrag.ignoreBytes}
      active-defrag-threshold-lower ${toString instance.activeDefrag.thresholdLower}
      active-defrag-threshold-upper ${toString instance.activeDefrag.thresholdUpper}
      active-defrag-cycle-min ${toString instance.activeDefrag.cycleMin}
      active-defrag-cycle-max ${toString instance.activeDefrag.cycleMax}
      client-output-buffer-limit normal ${buffers.normal.hard} ${buffers.normal.soft} ${toString buffers.normal.seconds}
      client-output-buffer-limit replica ${buffers.replica.hard} ${buffers.replica.soft} ${toString buffers.replica.seconds}
      client-output-buffer-limit pubsub ${buffers.pubsub.hard} ${buffers.pubsub.soft} ${toString buffers.pubsub.seconds}
      slowlog-log-slower-than ${toString instance.slowlogLogSlowerThan}
      slowlog-max-len ${toString instance.slowlogMaxLen}
      latency-monitor-threshold ${toString instance.latencyMonitorThreshold}

      ${lib.optionalString instance.authentication.enable "aclfile ${aclFile}"}
      ${moduleLines}
      ${extra}
    '';
  mkValidator =
    name: instance:
    let
      configFile = mkConfig name instance;
    in
    pkgs.writeShellScript "${name}-redis-config-validate" ''
      set -euo pipefail
      # ExecStartPre runs as the service user. Use a private temporary path,
      # never the production data directory or RuntimeDirectory.
      validation_dir="$(${pkgs.coreutils}/bin/mktemp -d)"
      validation_config="$validation_dir/redis.conf"
      socket="$validation_dir/redis.sock"
      ${pkgs.coreutils}/bin/cp ${q configFile} "$validation_config"
      ${pkgs.coreutils}/bin/printf '%s\n' \
        'port 0' \
        'tls-port 0' \
        "unixsocket $socket" \
        'unixsocketperm 0700' \
        "dir $validation_dir" \
        'dbfilename validation.rdb' \
        'appendonly no' \
        'save ""' \
        >> "$validation_config"
      ${redisPkg}/bin/redis-server "$validation_config" &
      validator_pid=$!
      cleanup() {
        ${pkgs.coreutils}/bin/kill -TERM "$validator_pid" 2>/dev/null || true
        wait "$validator_pid" 2>/dev/null || true
        # validation_dir is allocated by mktemp above. Remove its config and
        # private socket after the child has stopped; no production path is
        # ever involved in this parser/start probe.
        ${pkgs.findutils}/bin/find "$validation_dir" -depth -delete
      }
      trap cleanup EXIT
      for _ in $(${pkgs.coreutils}/bin/seq 1 100); do
        [ -S "$socket" ] && exit 0
        if ! ${pkgs.coreutils}/bin/kill -0 "$validator_pid" 2>/dev/null; then
          wait "$validator_pid"
          exit 1
        fi
        ${pkgs.coreutils}/bin/sleep 0.05
      done
      echo "Redis configuration validation timed out for ${name}" >&2
      exit 1
    '';
  mkService =
    name: instance:
    let
      configFile = mkConfig name instance;
    in
    lib.nameValuePair name {
      description = "Redis Open Source instance ${name}";
      requires = [ "db-quota-${name}.service" ];
      after = [
        "network.target"
        "db-quota-${name}.service"
      ];
      unitConfig.RequiresMountsFor = instance.dataDir;
      restartTriggers = [
        configFile
      ]
      ++ lib.optional instance.authentication.enable (mkAclFile name instance);
      serviceConfig = {
        Type = "notify";
        User = name;
        Group = name;
        RuntimeDirectory = name;
        RuntimeDirectoryMode = "0750";
        # The isolated parser/start validation only needs a private temporary
        # directory. The '+' prefix lets that pre-start probe create it despite
        # ProtectSystem=strict; Redis itself still runs as the instance user
        # under the service sandbox below.
        ExecStartPre = "+${mkValidator name instance}";
        ExecStart = "${redisPkg}/bin/redis-server ${configFile}";
        Restart = "on-failure";
        RestartSec = "2s";
        Slice = "database.slice";
        CPUWeight = instance.cpuWeight;
        # Omit CPUQuota: systemd's default is unlimited.  Recent systemd
        # releases reject the literal `CPUQuota=infinity` even though that is
        # the effective default, so writing it produces a misleading warning.
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
  options.services.nixdb.redis = {
    enable = lib.mkEnableOption "Redis Open Source instances" // {
      default = true;
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = nixdbPackages.redis;
      defaultText = lib.literalExpression "nixdb's independently pinned Redis Open Source package";
    };
    declaredVersion = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = nixdbVersions.redis;
    };
    instances = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            dataDir = lib.mkOption { type = lib.types.strMatching "^/.*"; };
            mountPoint = lib.mkOption { type = lib.types.strMatching "^/.*"; };
            projectId = lib.mkOption { type = lib.types.ints.positive; };
            diskLimit = lib.mkOption { type = sizeType; };
            port = lib.mkOption {
              type = lib.types.nullOr lib.types.port;
              default = 6379;
              description = "Plain Redis TCP port; null disables the TCP listener.";
            };
            bind = lib.mkOption {
              type = lib.types.listOf (lib.types.addCheck lib.types.nonEmptyStr noNewline);
              default = [ "127.0.0.1" ];
            };
            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
            protectedMode = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            tcpBacklog = lib.mkOption {
              type = lib.types.ints.positive;
              default = 511;
            };
            timeout = lib.mkOption {
              type = lib.types.ints.between 0 2147483647;
              default = 0;
            };
            tcpKeepalive = lib.mkOption {
              type = lib.types.ints.positive;
              default = 300;
            };
            databases = lib.mkOption {
              type = lib.types.ints.positive;
              default = 16;
            };
            unixSocket = lib.mkOption {
              type = lib.types.nullOr (lib.types.strMatching "^/.*");
              default = null;
            };
            unixSocketPerm = lib.mkOption {
              type = lib.types.strMatching "^0[0-7]{3,4}$";
              default = "0700";
            };

            maxMemory = lib.mkOption { type = sizeType; };
            maxMemoryPolicy = lib.mkOption {
              type = lib.types.enum [
                "volatile-lru"
                "allkeys-lru"
                "volatile-lfu"
                "allkeys-lfu"
                "volatile-random"
                "allkeys-random"
                "volatile-ttl"
                "noeviction"
              ];
              default = "noeviction";
            };
            maxMemorySamples = lib.mkOption {
              type = lib.types.ints.positive;
              default = 5;
            };

            cpuWeight = lib.mkOption { type = lib.types.ints.between 1 10000; };
            memoryHigh = lib.mkOption { type = sizeType; };
            memoryMax = lib.mkOption { type = sizeType; };
            memorySwapMax = lib.mkOption {
              type = sizeType;
              default = "0";
            };

            authentication = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
              };
              adminUser = lib.mkOption {
                type = lib.types.addCheck lib.types.nonEmptyStr safeUser;
                default = "nixdb-admin";
              };
              password = lib.mkOption {
                type = lib.types.addCheck lib.types.nonEmptyStr token;
                default = "CHANGE_ME";
              };
              defaultUser = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                password = lib.mkOption {
                  type = lib.types.nullOr (lib.types.addCheck lib.types.nonEmptyStr token);
                  default = null;
                };
                commands = lib.mkOption {
                  type = lib.types.listOf (lib.types.addCheck lib.types.str token);
                  default = [ "+@all" ];
                };
                keys = lib.mkOption {
                  type = lib.types.listOf (lib.types.addCheck lib.types.str token);
                  default = [ "~*" ];
                };
                channels = lib.mkOption {
                  type = lib.types.listOf (lib.types.addCheck lib.types.str token);
                  default = [ "&*" ];
                };
              };
              users = lib.mkOption {
                default = { };
                type = lib.types.attrsOf (
                  lib.types.submodule {
                    options = {
                      enable = lib.mkOption {
                        type = lib.types.bool;
                        default = true;
                      };
                      password = lib.mkOption {
                        type = lib.types.nullOr (lib.types.addCheck lib.types.nonEmptyStr token);
                        default = null;
                      };
                      commands = lib.mkOption {
                        type = lib.types.listOf (lib.types.addCheck lib.types.str token);
                        default = [ "+@all" ];
                      };
                      keys = lib.mkOption {
                        type = lib.types.listOf (lib.types.addCheck lib.types.str token);
                        default = [ "~*" ];
                      };
                      channels = lib.mkOption {
                        type = lib.types.listOf (lib.types.addCheck lib.types.str token);
                        default = [ "&*" ];
                      };
                    };
                  }
                );
              };
            };

            tls = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              port = lib.mkOption {
                type = lib.types.port;
                default = 6380;
              };
              openFirewall = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              certFile = lib.mkOption {
                type = lib.types.nullOr (lib.types.strMatching "^/.*");
                default = null;
              };
              keyFile = lib.mkOption {
                type = lib.types.nullOr (lib.types.strMatching "^/.*");
                default = null;
              };
              caFile = lib.mkOption {
                type = lib.types.nullOr (lib.types.strMatching "^/.*");
                default = null;
              };
              authClients = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              healthClientCertFile = lib.mkOption {
                type = lib.types.nullOr (lib.types.strMatching "^/.*");
                default = null;
              };
              healthClientKeyFile = lib.mkOption {
                type = lib.types.nullOr (lib.types.strMatching "^/.*");
                default = null;
              };
            };

            persistence = {
              appendOnly = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              appendFsync = lib.mkOption {
                type = lib.types.enum [
                  "always"
                  "everysec"
                  "no"
                ];
                default = "everysec";
              };
              noAppendfsyncOnRewrite = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              autoAofRewritePercentage = lib.mkOption {
                type = lib.types.ints.positive;
                default = 100;
              };
              autoAofRewriteMinSize = lib.mkOption {
                type = sizeType;
                default = "64M";
              };
              aofUseRdbPreamble = lib.mkOption {
                type = lib.types.bool;
                default = true;
              };
              appendDirName = lib.mkOption {
                type = lib.types.addCheck lib.types.nonEmptyStr token;
                default = "appendonlydir";
              };
              aofLoadTruncated = lib.mkOption {
                type = lib.types.bool;
                default = true;
              };
              saveRules = lib.mkOption {
                default = [
                  {
                    seconds = 3600;
                    changes = 1;
                  }
                  {
                    seconds = 300;
                    changes = 100;
                  }
                  {
                    seconds = 60;
                    changes = 10000;
                  }
                ];
                type = lib.types.listOf (
                  lib.types.submodule {
                    options = {
                      seconds = lib.mkOption { type = lib.types.ints.positive; };
                      changes = lib.mkOption { type = lib.types.ints.positive; };
                    };
                  }
                );
              };
              dbFilename = lib.mkOption {
                type = lib.types.addCheck lib.types.nonEmptyStr token;
                default = "dump.rdb";
              };
              rdbCompression = lib.mkOption {
                type = lib.types.bool;
                default = true;
              };
              rdbChecksum = lib.mkOption {
                type = lib.types.bool;
                default = true;
              };
            };

            ioThreads = lib.mkOption {
              type = lib.types.ints.between 1 128;
              default = 1;
            };
            ioThreadsDoReads = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
            hz = lib.mkOption {
              type = lib.types.ints.between 1 500;
              default = 10;
            };
            dynamicHz = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            activeRehashing = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            lazyfree = {
              lazyEviction = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              lazyExpire = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              lazyServerDel = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              replicaLazyFlush = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
            };
            activeDefrag = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              ignoreBytes = lib.mkOption {
                type = sizeType;
                default = "100M";
              };
              thresholdLower = lib.mkOption {
                type = lib.types.ints.between 1 100;
                default = 10;
              };
              thresholdUpper = lib.mkOption {
                type = lib.types.ints.between 1 100;
                default = 100;
              };
              cycleMin = lib.mkOption {
                type = lib.types.ints.between 1 100;
                default = 1;
              };
              cycleMax = lib.mkOption {
                type = lib.types.ints.between 1 100;
                default = 25;
              };
            };
            clientOutputBufferLimits = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options = {
                    hard = lib.mkOption { type = sizeType; };
                    soft = lib.mkOption { type = sizeType; };
                    seconds = lib.mkOption { type = lib.types.ints.between 0 2147483647; };
                  };
                }
              );
              default = {
                normal = {
                  hard = "0";
                  soft = "0";
                  seconds = 0;
                };
                replica = {
                  hard = "256M";
                  soft = "64M";
                  seconds = 60;
                };
                pubsub = {
                  hard = "32M";
                  soft = "8M";
                  seconds = 60;
                };
              };
            };
            slowlogLogSlowerThan = lib.mkOption {
              type = lib.types.ints.between (-1) 2147483647;
              default = 10000;
            };
            slowlogMaxLen = lib.mkOption {
              type = lib.types.ints.positive;
              default = 128;
            };
            latencyMonitorThreshold = lib.mkOption {
              type = lib.types.ints.between 0 2147483647;
              default = 0;
            };

            extraConfig = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.oneOf [
                  lib.types.bool
                  lib.types.int
                  lib.types.str
                  (lib.types.listOf (
                    lib.types.oneOf [
                      lib.types.bool
                      lib.types.int
                      lib.types.str
                    ]
                  ))
                ]
              );
              default = { };
              description = "Direct Redis 8 directive values. Lists render repeated directives; collisions with nixdb-owned directives are evaluation errors.";
            };
            extraConfigLines = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Direct single-line Redis 8 configuration for directives needing syntax beyond extraConfig.";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf (config.services.nixdb.enable && cfg.enable) {
    assertions = [
      {
        assertion = lib.getVersion redisPkg == cfg.declaredVersion;
        message = "services.nixdb.redis: declared version ${cfg.declaredVersion} does not match package ${lib.getVersion redisPkg}.";
      }
      {
        assertion =
          redisPkg ? bundledModules
          && redisPkg ? builtInFeatures
          &&
            redisPkg.bundledModules == [
              "redisbloom"
              "redisearch"
              "rejson"
              "redistimeseries"
            ]
          && redisPkg.builtInFeatures == [ "vector-sets" ];
        message = "services.nixdb.redis: selected package does not expose the required Redis 8 bundled module set.";
      }
      {
        assertion = lib.all (instance: parseSize instance.maxMemory <= parseSize instance.memoryMax) (
          lib.attrValues instances
        );
        message = "services.nixdb.redis: maxMemory must not exceed the systemd MemoryMax; leave explicit RSS/fork/rewrite headroom.";
      }
      {
        assertion = lib.all (
          instance: instance.port != null || instance.tls.enable || instance.unixSocket != null
        ) (lib.attrValues instances);
        message = "services.nixdb.redis: each instance needs a TCP, TLS, or Unix-socket listener.";
      }
      {
        assertion = lib.all (
          instance:
          !instance.tls.enable
          || (instance.tls.certFile != null && instance.tls.keyFile != null && instance.tls.caFile != null)
        ) (lib.attrValues instances);
        message = "services.nixdb.redis: enabled TLS requires certFile, keyFile, and caFile.";
      }
      {
        assertion = lib.all (
          instance:
          !instance.tls.enable
          || !instance.tls.authClients
          || (instance.tls.healthClientCertFile != null && instance.tls.healthClientKeyFile != null)
        ) (lib.attrValues instances);
        message = "services.nixdb.redis: tls.authClients requires healthClientCertFile and healthClientKeyFile for mutual TLS health probes.";
      }
      {
        assertion = lib.all (
          instance:
          !instance.tls.authClients
          || (
            instance.tls.enable
            && instance.tls.healthClientCertFile != null
            && instance.tls.healthClientKeyFile != null
          )
        ) (lib.attrValues instances);
        message = "services.nixdb.redis: TLS client authentication requires TLS and health client certificate/key paths.";
      }
      {
        assertion = lib.all (
          instance:
          !instance.authentication.enable
          || lib.all safeUser (builtins.attrNames instance.authentication.users)
        ) (lib.attrValues instances);
        message = "services.nixdb.redis: ACL user names may contain only letters, numbers, underscores, and hyphens.";
      }
      {
        assertion = lib.all (
          instance:
          !instance.authentication.enable
          || !(builtins.hasAttr instance.authentication.adminUser instance.authentication.users)
        ) (lib.attrValues instances);
        message = "services.nixdb.redis: authentication.adminUser is managed by nixdb and must not be duplicated in authentication.users.";
      }
      {
        assertion = lib.all rawValuesSafe (lib.attrValues instances);
        message = "services.nixdb.redis: extraConfig names and values must be single-line safe Redis directives.";
      }
      {
        assertion = lib.all rawNoCollision (lib.attrValues instances);
        message = "services.nixdb.redis: extraConfig/extraConfigLines may not override a nixdb-owned Redis directive.";
      }
    ];

    services.nixdb._internal.instances = lib.mapAttrsToList (name: instance: {
      inherit name;
      kind = "redis";
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
      engineMemoryLimit = instance.maxMemory;
      ports =
        lib.optional (instance.port != null) instance.port
        ++ lib.optional instance.tls.enable instance.tls.port;
      firewallPorts =
        lib.optional (instance.port != null && instance.openFirewall) instance.port
        ++ lib.optional (instance.tls.enable && instance.tls.openFirewall) instance.tls.port;
      unixSockets = lib.optional (instance.unixSocket != null) instance.unixSocket;
      listeners = lib.concatMap (
        address:
        lib.optional (instance.port != null) {
          inherit address;
          port = instance.port;
        }
        ++ lib.optional instance.tls.enable {
          inherit address;
          port = instance.tls.port;
        }
      ) instance.bind;
      internalCache = {
        kind = "Redis maxmemory";
        value = instance.maxMemory;
      };
      engineMetadata = {
        maxMemory = instance.maxMemory;
        maxMemoryPolicy = instance.maxMemoryPolicy;
        maxMemorySamples = instance.maxMemorySamples;
        persistence = persistenceMode instance;
        appendFsync = if instance.persistence.appendOnly then instance.persistence.appendFsync else null;
        rdb = {
          enable = instance.persistence.saveRules != [ ];
          dbFilename = instance.persistence.dbFilename;
          compression = instance.persistence.rdbCompression;
          checksum = instance.persistence.rdbChecksum;
        };
        tls = {
          enable = instance.tls.enable;
          port = if instance.tls.enable then instance.tls.port else null;
        };
        unixSocket = instance.unixSocket;
        modules = redisPkg.bundledModules;
        builtInFeatures = redisPkg.builtInFeatures;
      };
    }) instances;

    services.nixdb._internal.healthCredentials = lib.mapAttrsToList (name: instance: {
      inherit name;
      engine = "redis";
      address = builtins.head instance.bind;
      username = if instance.authentication.enable then instance.authentication.adminUser else "";
      password = if instance.authentication.enable then instance.authentication.password else "";
      authenticated = instance.authentication.enable;
      unixSocket = instance.unixSocket;
      ports =
        (lib.optionalAttrs (instance.port != null) { redis = instance.port; })
        // (lib.optionalAttrs instance.tls.enable { tls = instance.tls.port; });
      tls = {
        enable = instance.tls.enable;
        caFile = instance.tls.caFile;
        clientCertFile = instance.tls.healthClientCertFile;
        clientKeyFile = instance.tls.healthClientKeyFile;
      };
    }) instances;

    environment.systemPackages = [ redisPkg ];
    systemd.services = lib.mapAttrs' mkService instances;
  };
}
