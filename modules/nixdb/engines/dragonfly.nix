# SPDX-License-Identifier: GPL-3.0-or-later
{
  config,
  lib,
  nixdbPackages,
  nixdbVersions,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.services.nixdb.dragonfly;
  instances = cfg.instances;
  dragonflyPkg = cfg.package;
  inherit (import ../../../lib/sizes.nix { inherit lib; }) parseSize;

  sizeType = lib.types.strMatching "^[0-9]+[KMGTPEkmgtpe]?$";
  noNewline = value: !lib.hasInfix "\n" value && !lib.hasInfix "\r" value;
  # Dragonfly's ACL parser accepts the same conservative, shell-safe user-name
  # alphabet that nixdb uses for Redis. User names are ACL tokens, never shell.
  safeUser = value: builtins.match "^[A-Za-z0-9_-]+$" value != null;
  token = value: builtins.match "^[^[:space:]]+$" value != null;
  flagValue =
    value:
    if builtins.isBool value then
      (if value then "true" else "false")
    else if builtins.isInt value then
      toString value
    else if builtins.isFloat value then
      toString value
    else
      value;
  asList = value: if builtins.isList value then value else [ value ];
  typedFlags = [
    "port"
    "bind"
    "dir"
    "dbfilename"
    "pidfile"
    "user"
    "maxmemory"
    "proactor_threads"
    "cache_mode"
    "eviction_memory_budget_threshold"
    "rss_oom_deny_ratio"
    "snapshot_cron"
    "df_snapshot_format"
    "s3_endpoint"
    "s3_use_https"
    "s3_sign_payload"
    "s3_ec2_metadata"
    "requirepass"
    "aclfile"
    "tls"
    "tls_cert_file"
    "tls_key_file"
    "tls_ca_cert_file"
    "no_tls_on_admin_port"
    "tls_replication"
    "memcached_port"
    "admin_port"
    "admin_bind"
    "cluster_mode"
    "replicaof"
    "masterauth"
    "masteruser"
    "tiered_prefix"
    "tiered_max_file_size"
    "tiered_offload_threshold"
    "tiered_upload_threshold"
    "tiered_min_value_size"
    "tiered_max_pending_stash_bytes"
  ];
  rawNames = instance: builtins.attrNames instance.extraFlags;
  rawValuesSafe =
    instance:
    lib.all (name: builtins.match "^[A-Za-z0-9_]+$" name != null) (rawNames instance)
    && lib.all (
      value: lib.all (item: if builtins.isString item then noNewline item else true) (asList value)
    ) (builtins.attrValues instance.extraFlags);
  rawNoCollision = instance: lib.intersectLists typedFlags (rawNames instance) == [ ];
  renderFlag = name: value: "--${name}=${flagValue value}";
  renderExtra =
    instance:
    lib.concatMap (name: map (value: renderFlag name value) (asList instance.extraFlags.${name})) (
      builtins.attrNames instance.extraFlags
    );
  mkFlagValidator =
    name: instance:
    pkgs.writeShellScript "validate-dragonfly-${name}-flags" ''
      set -eu
      help="$(${dragonflyPkg}/bin/dragonfly --help 2>&1 || true)"
      ${lib.concatMapStringsSep "\n" (flag: ''
        printf '%s\n' "$help" | grep -F -- "--${flag}" >/dev/null || {
          echo "nixdb Dragonfly ${name}: unsupported pinned-binary flag --${flag}" >&2
          exit 1
        }
      '') (rawNames instance)}
    '';
  renderAclUser =
    name: user:
    lib.concatStringsSep " " (
      [
        "USER"
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
    pkgs.writeText "${name}.dragonfly.acl" (
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
  mkArgs =
    name: instance:
    let
      tls = instance.tls;
      persistence = instance.persistence;
      tiering = instance.tiering;
      aclFile = mkAclFile name instance;
    in
    [
      "--bind=${instance.bindAddress}"
      "--port=${toString instance.port}"
      "--dir=${
        if persistence.s3.directoryUrl == null then instance.dataDir else persistence.s3.directoryUrl
      }"
      "--dbfilename=${persistence.dbFilename}"
      "--df_snapshot_format=${if persistence.dfSnapshotFormat then "true" else "false"}"
      "--maxmemory=${instance.maxMemory}"
      "--proactor_threads=${toString instance.proactorThreads}"
      "--cache_mode=${if instance.cacheMode then "true" else "false"}"
      "--eviction_memory_budget_threshold=${toString instance.evictionMemoryBudgetThreshold}"
      "--rss_oom_deny_ratio=${toString instance.rssOomDenyRatio}"
      "--snapshot_cron=${persistence.snapshotCron}"
      "--s3_endpoint=${if persistence.s3.endpoint == null then "" else persistence.s3.endpoint}"
      "--s3_use_https=${if persistence.s3.useHttps then "true" else "false"}"
      "--s3_sign_payload=${if persistence.s3.signPayload then "true" else "false"}"
      "--s3_ec2_metadata=${if persistence.s3.ec2Metadata then "true" else "false"}"
      "--tls=${if tls.enable then "true" else "false"}"
      "--memcached_port=${toString instance.memcached.port}"
      "--admin_port=${toString instance.admin.port}"
      "--admin_bind=${instance.admin.bindAddress}"
      "--cluster_mode=${instance.clusterMode}"
      "--replicaof=${instance.replication.replicaOf}"
      "--tiered_prefix=${if tiering.enable then tiering.prefix else ""}"
      "--tiered_max_file_size=${if tiering.enable then tiering.maxFileSize else "0"}"
      "--tiered_offload_threshold=${toString tiering.offloadThreshold}"
      "--tiered_upload_threshold=${toString tiering.uploadThreshold}"
      "--tiered_min_value_size=${toString tiering.minValueSize}"
      "--tiered_max_pending_stash_bytes=${tiering.maxPendingStashBytes}"
    ]
    # The generated ACL defines the managed admin user and disables the
    # default user by default. Supplying --requirepass as well is redundant
    # and would place the password in systemd's ExecStart/process display.
    ++ lib.optionals instance.authentication.enable [ "--aclfile=${aclFile}" ]
    ++ lib.optionals tls.enable [
      "--tls_cert_file=${tls.certFile}"
      "--tls_key_file=${tls.keyFile}"
      "--tls_ca_cert_file=${tls.caFile}"
      "--no_tls_on_admin_port=${if tls.allowPlainAdmin then "true" else "false"}"
    ]
    ++ lib.optional (
      instance.replication.masterAuth != null
    ) "--masterauth=${instance.replication.masterAuth}"
    ++ lib.optional (
      instance.replication.masterUser != null
    ) "--masteruser=${instance.replication.masterUser}"
    ++ lib.optional instance.replication.tls "--tls_replication=true"
    ++ renderExtra instance;
  mkService =
    name: instance:
    let
      args = mkArgs name instance;
    in
    lib.nameValuePair name {
      description = "Dragonfly instance ${name}";
      requires = [ "db-quota-${name}.service" ];
      after = [
        "network.target"
        "db-quota-${name}.service"
      ];
      unitConfig.RequiresMountsFor = [
        instance.dataDir
      ]
      ++ lib.optional instance.tiering.enable instance.tiering.prefix;
      restartTriggers = lib.optional instance.authentication.enable (mkAclFile name instance);
      serviceConfig = {
        Type = "simple";
        User = name;
        Group = name;
        RuntimeDirectory = name;
        RuntimeDirectoryMode = "0750";
        ExecStartPre = mkFlagValidator name instance;
        ExecStart = utils.escapeSystemdExecArgs ([ "${dragonflyPkg}/bin/dragonfly" ] ++ args);
        Restart = "on-failure";
        RestartSec = "2s";
        Slice = "database.slice";
        CPUWeight = instance.cpuWeight;
        # No CPUQuota is an unlimited CPU quota in systemd.  Do not render
        # `CPUQuota=infinity`: current systemd rejects that literal.
        MemoryHigh = instance.memoryHigh;
        MemoryMax = instance.memoryMax;
        MemorySwapMax = instance.memorySwapMax;
        LimitNOFILE = 65536;
        UMask = "0077";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [
          instance.dataDir
        ];
      };
    };
in
{
  options.services.nixdb.dragonfly = {
    enable = lib.mkEnableOption "Dragonfly instances" // {
      default = true;
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = nixdbPackages.dragonfly;
      defaultText = lib.literalExpression "nixdb's independently pinned Dragonfly package";
    };
    declaredVersion = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = nixdbVersions.dragonfly;
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
              type = lib.types.port;
              default = 6379;
            };
            bindAddress = lib.mkOption {
              type = lib.types.addCheck lib.types.nonEmptyStr noNewline;
              default = "127.0.0.1";
            };
            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };

            maxMemory = lib.mkOption { type = sizeType; };
            cacheMode = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
            evictionMemoryBudgetThreshold = lib.mkOption {
              type = lib.types.float;
              default = 0.1;
            };
            rssOomDenyRatio = lib.mkOption {
              type = lib.types.float;
              default = 1.25;
            };
            proactorThreads = lib.mkOption {
              type = lib.types.ints.positive;
              default = 1;
              description = "Dragonfly I/O/shard threads. Dragonfly v1.40.1 requires at least 256 MiB of maxMemory per configured thread; increase deliberately for throughput.";
            };
            cpuWeight = lib.mkOption { type = lib.types.ints.between 1 10000; };
            memoryHigh = lib.mkOption { type = sizeType; };
            memoryMax = lib.mkOption { type = sizeType; };
            memorySwapMax = lib.mkOption {
              type = sizeType;
              default = "0";
            };

            persistence = {
              dbFilename = lib.mkOption {
                type = lib.types.addCheck lib.types.nonEmptyStr token;
                default = "dump-{timestamp}";
                description = "Snapshot filename. With dfSnapshotFormat=true (the default), Dragonfly requires a name without an extension.";
              };
              dfSnapshotFormat = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Use Dragonfly's native snapshot format. Set false only when deliberately using Redis-compatible RDB snapshots.";
              };
              snapshotCron = lib.mkOption {
                type = lib.types.str;
                default = "";
              };
              aof = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Always rejected: Dragonfly v1.40.1 has no AOF persistence.";
                };
              };
              s3 = {
                directoryUrl = lib.mkOption {
                  type = lib.types.nullOr (lib.types.strMatching "^s3://.*");
                  default = null;
                };
                endpoint = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                };
                useHttps = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
                signPayload = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
                ec2Metadata = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
              };
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
              allowPlainAdmin = lib.mkOption {
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

            memcached = {
              port = lib.mkOption {
                type = lib.types.port;
                default = 0;
              };
              openFirewall = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
            };
            admin = {
              port = lib.mkOption {
                type = lib.types.port;
                default = 0;
              };
              bindAddress = lib.mkOption {
                type = lib.types.addCheck lib.types.nonEmptyStr noNewline;
                default = "127.0.0.1";
              };
              openFirewall = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
            };
            clusterMode = lib.mkOption {
              type = lib.types.enum [
                ""
                "emulated"
                "yes"
              ];
              default = "";
            };
            replication = {
              replicaOf = lib.mkOption {
                type = lib.types.str;
                default = "";
              };
              masterUser = lib.mkOption {
                type = lib.types.nullOr (lib.types.addCheck lib.types.nonEmptyStr token);
                default = null;
              };
              masterAuth = lib.mkOption {
                type = lib.types.nullOr (lib.types.addCheck lib.types.nonEmptyStr token);
                default = null;
              };
              tls = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
            };
            tiering = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              prefix = lib.mkOption {
                type = lib.types.nullOr (lib.types.strMatching "^/.*");
                default = null;
              };
              mountPoint = lib.mkOption {
                type = lib.types.nullOr (lib.types.strMatching "^/.*");
                default = null;
              };
              maxFileSize = lib.mkOption {
                type = sizeType;
                default = "256M";
              };
              offloadThreshold = lib.mkOption {
                type = lib.types.float;
                default = 0.5;
              };
              uploadThreshold = lib.mkOption {
                type = lib.types.float;
                default = 0.1;
              };
              minValueSize = lib.mkOption {
                type = lib.types.ints.between 64 2147483647;
                default = 64;
              };
              maxPendingStashBytes = lib.mkOption {
                type = sizeType;
                default = "256K";
              };
            };
            extraFlags = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.oneOf [
                  lib.types.bool
                  lib.types.int
                  lib.types.float
                  lib.types.str
                  (lib.types.listOf (
                    lib.types.oneOf [
                      lib.types.bool
                      lib.types.int
                      lib.types.float
                      lib.types.str
                    ]
                  ))
                ]
              );
              default = { };
              description = "Direct Dragonfly v1.40.1 flags. Lists render repeated flags; collisions with nixdb-owned flags are evaluation errors.";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf (config.services.nixdb.enable && cfg.enable) {
    assertions = [
      {
        assertion = lib.getVersion dragonflyPkg == cfg.declaredVersion;
        message = "services.nixdb.dragonfly: declared version ${cfg.declaredVersion} does not match package ${lib.getVersion dragonflyPkg}.";
      }
      {
        assertion = lib.all (instance: parseSize instance.maxMemory <= parseSize instance.memoryMax) (
          lib.attrValues instances
        );
        message = "services.nixdb.dragonfly: maxMemory must not exceed systemd MemoryMax; leave explicit RSS/internal overhead headroom.";
      }
      {
        assertion = lib.all (
          instance: parseSize instance.maxMemory >= 256 * 1024 * 1024 * instance.proactorThreads
        ) (lib.attrValues instances);
        message = "services.nixdb.dragonfly: Dragonfly v1.40.1 requires maxMemory of at least 256 MiB per proactorThreads thread.";
      }
      {
        assertion = lib.all (
          instance:
          instance.evictionMemoryBudgetThreshold >= 0.0 && instance.evictionMemoryBudgetThreshold <= 1.0
        ) (lib.attrValues instances);
        message = "services.nixdb.dragonfly: evictionMemoryBudgetThreshold must be between 0 and 1.";
      }
      {
        assertion = lib.all (instance: instance.rssOomDenyRatio < 0.0 || instance.rssOomDenyRatio >= 1.0) (
          lib.attrValues instances
        );
        message = "services.nixdb.dragonfly: rssOomDenyRatio must be negative to disable or at least 1.0.";
      }
      {
        assertion = lib.all (instance: !instance.persistence.aof.enable) (lib.attrValues instances);
        message = "services.nixdb.dragonfly: Dragonfly v1.40.1 does not support AOF persistence; use snapshotCron/local or S3 snapshots.";
      }
      {
        assertion = lib.all (
          instance:
          !instance.persistence.dfSnapshotFormat
          || builtins.match ".*\\.[^/]+$" instance.persistence.dbFilename == null
        ) (lib.attrValues instances);
        message = "services.nixdb.dragonfly: native Dragonfly snapshots require persistence.dbFilename without a filename extension; set dfSnapshotFormat = false for an RDB filename.";
      }
      {
        assertion = lib.all (
          instance:
          !instance.tls.enable
          || (instance.tls.certFile != null && instance.tls.keyFile != null && instance.tls.caFile != null)
        ) (lib.attrValues instances);
        message = "services.nixdb.dragonfly: enabled TLS requires certFile, keyFile, and caFile.";
      }
      {
        assertion = lib.all (
          instance:
          !instance.tls.enable
          || (instance.tls.healthClientCertFile != null && instance.tls.healthClientKeyFile != null)
        ) (lib.attrValues instances);
        message = "services.nixdb.dragonfly: enabled TLS requires healthClientCertFile and healthClientKeyFile; Dragonfly v1.40.1 validates TLS with tls_ca_cert_file and requires mutual TLS for health probes.";
      }
      {
        assertion = lib.all (
          instance:
          !instance.tiering.enable
          || (
            instance.tiering.prefix != null
            && instance.tiering.mountPoint != null
            && lib.hasPrefix "${instance.dataDir}/" instance.tiering.prefix
          )
        ) (lib.attrValues instances);
        message = "services.nixdb.dragonfly: enabled SSD tiering requires an absolute prefix beneath dataDir, so tier files are inside the instance's XFS project quota.";
      }
      {
        assertion = lib.all (
          instance: !instance.tiering.enable || instance.tiering.mountPoint == instance.mountPoint
        ) (lib.attrValues instances);
        message = "services.nixdb.dragonfly: v0.3.0 requires tiered storage under the instance's quota-managed mountPoint; a separate quota model is not silently assumed.";
      }
      {
        assertion = lib.all (
          instance: !instance.tiering.enable || parseSize instance.tiering.maxFileSize >= 256 * 1024 * 1024
        ) (lib.attrValues instances);
        message = "services.nixdb.dragonfly: Dragonfly v1.40.1 tiered_max_file_size must be at least 256M when tiering is enabled.";
      }
      {
        assertion = lib.all (
          instance:
          !instance.authentication.enable
          || lib.all safeUser (builtins.attrNames instance.authentication.users)
        ) (lib.attrValues instances);
        message = "services.nixdb.dragonfly: ACL user names may contain only letters, numbers, underscores, and hyphens.";
      }
      {
        assertion = lib.all (
          instance:
          !instance.authentication.enable
          || !(builtins.hasAttr instance.authentication.adminUser instance.authentication.users)
        ) (lib.attrValues instances);
        message = "services.nixdb.dragonfly: authentication.adminUser is managed by nixdb and must not be duplicated in authentication.users.";
      }
      {
        assertion = lib.all rawValuesSafe (lib.attrValues instances);
        message = "services.nixdb.dragonfly: extraFlags names and string values must be safe single-line flag data.";
      }
      {
        assertion = lib.all rawNoCollision (lib.attrValues instances);
        message = "services.nixdb.dragonfly: extraFlags may not override a nixdb-owned Dragonfly flag.";
      }
    ];

    services.nixdb._internal.instances = lib.mapAttrsToList (name: instance: {
      inherit name;
      kind = "dragonfly";
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
      ports = [
        instance.port
      ]
      ++ lib.optional (instance.memcached.port != 0) instance.memcached.port
      ++ lib.optional (instance.admin.port != 0) instance.admin.port;
      firewallPorts =
        lib.optional instance.openFirewall instance.port
        ++ lib.optional (
          instance.memcached.port != 0 && instance.memcached.openFirewall
        ) instance.memcached.port
        ++ lib.optional (instance.admin.port != 0 && instance.admin.openFirewall) instance.admin.port;
      listeners = [
        {
          address = instance.bindAddress;
          port = instance.port;
        }
      ]
      ++ lib.optional (instance.memcached.port != 0) {
        address = instance.bindAddress;
        port = instance.memcached.port;
      }
      ++ lib.optional (instance.admin.port != 0) {
        address = instance.admin.bindAddress;
        port = instance.admin.port;
      };
      internalCache = {
        kind = "Dragonfly maxmemory";
        value = instance.maxMemory;
      };
      engineMetadata = {
        maxMemory = instance.maxMemory;
        proactorThreads = instance.proactorThreads;
        cacheMode = instance.cacheMode;
        evictionMemoryBudgetThreshold = instance.evictionMemoryBudgetThreshold;
        rssOomDenyRatio = instance.rssOomDenyRatio;
        snapshot = {
          dbFilename = instance.persistence.dbFilename;
          dfSnapshotFormat = instance.persistence.dfSnapshotFormat;
          snapshotCron = instance.persistence.snapshotCron;
          s3DirectoryUrl = instance.persistence.s3.directoryUrl;
          s3Endpoint = instance.persistence.s3.endpoint;
        };
        memcachedPort = if instance.memcached.port == 0 then null else instance.memcached.port;
        admin = {
          port = if instance.admin.port == 0 then null else instance.admin.port;
          bindAddress = instance.admin.bindAddress;
        };
        tiering = {
          enable = instance.tiering.enable;
          prefix = instance.tiering.prefix;
          mountPoint = instance.tiering.mountPoint;
        };
        clusterMode = instance.clusterMode;
        tls = {
          enable = instance.tls.enable;
          allowPlainAdmin = instance.tls.allowPlainAdmin;
        };
      };
    }) instances;

    services.nixdb._internal.healthCredentials = lib.mapAttrsToList (name: instance: {
      inherit name;
      engine = "dragonfly";
      address = instance.bindAddress;
      username = if instance.authentication.enable then instance.authentication.adminUser else "";
      password = if instance.authentication.enable then instance.authentication.password else "";
      authenticated = instance.authentication.enable;
      ports = {
        redis = instance.port;
      }
      // lib.optionalAttrs instance.tls.enable { tls = instance.port; }
      // lib.optionalAttrs (instance.memcached.port != 0) { memcached = instance.memcached.port; }
      // lib.optionalAttrs (instance.admin.port != 0) { admin = instance.admin.port; };
      tls = {
        enable = instance.tls.enable;
        caFile = instance.tls.caFile;
        clientCertFile = instance.tls.healthClientCertFile;
        clientKeyFile = instance.tls.healthClientKeyFile;
      };
    }) instances;

    # Dragonfly implements the Redis protocol but does not ship a command-line
    # client. The nixpkgs Redis package is installed solely for redis-cli health
    # probes; it is not the managed Dragonfly server and does not influence its
    # independently pinned Dragonfly version.
    environment.systemPackages = [
      dragonflyPkg
      pkgs.redis
    ];
    systemd.services = lib.mapAttrs' mkService instances;
  };
}
