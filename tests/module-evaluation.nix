# SPDX-License-Identifier: GPL-3.0-or-later
{
  nixpkgs,
  nixdbModule,
  pkgs,
}:

let
  lib = nixpkgs.lib;
  secret = "SUPER_SECRET_NIXDB_TEST_VALUE_9f31";
  mkSystem =
    extraModules:
    lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        nixdbModule
        ./eval-host.nix
      ]
      ++ extraModules;
    };
  valid = mkSystem [
    {
      services.nixdb.mongodb.instances.mongo-example.password = lib.mkForce secret;
    }
  ];
  manifest = valid.config.services.nixdb._internal.runtimeManifest;
  manifestJSON = builtins.toJSON manifest;

  evaluationSucceeds =
    system:
    (builtins.tryEval (builtins.deepSeq system.config.system.build.toplevel.drvPath true)).success;
  evaluationFails = system: !(evaluationSucceeds system);

  duplicatePort = mkSystem [
    {
      services.nixdb.mysql.instances.mysql-example.port = lib.mkForce 27017;
    }
  ];
  duplicateProject = mkSystem [
    {
      services.nixdb.mysql.instances.mysql-example.projectId = lib.mkForce 2001;
    }
  ];
  duplicateDataDir = mkSystem [
    {
      services.nixdb.mysql.instances.mysql-example.dataDir =
        lib.mkForce "/srv/databases/mongodb/mongo-example";
    }
  ];
  duplicateInMemoryPort = mkSystem [
    {
      services.nixdb.dragonfly.instances.dragonfly-example.memcached.port = lib.mkForce 6379;
    }
  ];
  invalidRedisMemory = mkSystem [
    {
      services.nixdb.redis.instances.redis-example.maxMemory = lib.mkForce "3G";
    }
  ];
  invalidDragonflyMemory = mkSystem [
    {
      services.nixdb.dragonfly.instances.dragonfly-example.maxMemory = lib.mkForce "3G";
    }
  ];
  invalidDragonflyThreadMemory = mkSystem [
    {
      services.nixdb.dragonfly.instances.dragonfly-example.maxMemory = lib.mkForce "128M";
    }
  ];
  invalidDragonflyAof = mkSystem [
    {
      services.nixdb.dragonfly.instances.dragonfly-example.persistence.aof.enable = true;
    }
  ];
  invalidDragonflyNativeSnapshotFilename = mkSystem [
    {
      services.nixdb.dragonfly.instances.dragonfly-example.persistence.dbFilename = "dump.rdb";
    }
  ];
  invalidDragonflyTieringPath = mkSystem [
    {
      services.nixdb.dragonfly.instances.dragonfly-example.tiering = {
        enable = true;
        mountPoint = "/";
        prefix = "/srv/unmanaged-dragonfly-tier";
      };
    }
  ];
  invalidRedisTls = mkSystem [
    {
      services.nixdb.redis.instances.redis-example.tls.enable = true;
    }
  ];
  invalidDragonflyTls = mkSystem [
    {
      services.nixdb.dragonfly.instances.dragonfly-example.tls.enable = true;
    }
  ];
  invalidRedisRawCollision = mkSystem [
    {
      services.nixdb.redis.instances.redis-example.extraConfig.port = 6390;
    }
  ];
  invalidDragonflyRawCollision = mkSystem [
    {
      services.nixdb.dragonfly.instances.dragonfly-example.extraFlags.port = 6390;
    }
  ];
  invalidDragonflyAclUser = mkSystem [
    {
      services.nixdb.dragonfly.instances.dragonfly-example.authentication.users."bad.user" = {
        password = "CHANGE_ME";
      };
    }
  ];
  socketOnlyRedis = mkSystem [
    {
      services.nixdb.redis.instances.redis-example = {
        port = lib.mkForce null;
        unixSocket = lib.mkForce "/run/redis-example/redis.sock";
      };
    }
  ];
  invalidMount = mkSystem [
    {
      services.nixdb.mongodb.instances.mongo-example.mountPoint = lib.mkForce "/missing";
    }
  ];
  invalidMemory = mkSystem [
    {
      services.nixdb.mongodb.instances.mongo-example.memoryHigh = lib.mkForce "3G";
      services.nixdb.mongodb.instances.mongo-example.memoryMax = lib.mkForce "2G";
    }
  ];
  invalidMongoCache = mkSystem [
    {
      services.nixdb.mongodb.instances.mongo-example.cacheGB = lib.mkForce 3;
      services.nixdb.mongodb.instances.mongo-example.memoryMax = lib.mkForce "2G";
    }
  ];
  invalidMysqlBuffer = mkSystem [
    {
      services.nixdb.mysql.instances.mysql-example.bufferPool = lib.mkForce "3G";
      services.nixdb.mysql.instances.mysql-example.memoryMax = lib.mkForce "2G";
    }
  ];
  minimal = lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      nixdbModule
      {
        boot.isContainer = true;
        networking.hostName = "minimal-db-host";
        system.stateVersion = "26.05";
        services.nixdb = {
          enable = true;
          operator.enable = false;
          mongodb.enable = false;
          mysql.enable = false;
          manticore.enable = false;
        };
      }
    ];
  };
in
assert evaluationSucceeds valid;
assert evaluationSucceeds minimal;
assert evaluationSucceeds socketOnlyRedis;
assert builtins.length manifest.instances == 5;
assert manifest.schemaVersion == 1;
assert manifest.instances != [ ];
assert (builtins.head manifest.instances).serviceName != "";
assert lib.hasInfix "WiredTiger cache" manifestJSON;
assert !(lib.hasInfix secret manifestJSON);
assert evaluationFails duplicatePort;
assert evaluationFails duplicateProject;
assert evaluationFails duplicateDataDir;
assert evaluationFails invalidMount;
assert evaluationFails invalidMemory;
assert evaluationFails invalidMongoCache;
assert evaluationFails invalidMysqlBuffer;
assert evaluationFails duplicateInMemoryPort;
assert evaluationFails invalidRedisMemory;
assert evaluationFails invalidDragonflyMemory;
assert evaluationFails invalidDragonflyThreadMemory;
assert evaluationFails invalidDragonflyAof;
assert evaluationFails invalidDragonflyNativeSnapshotFilename;
assert evaluationFails invalidDragonflyTieringPath;
assert evaluationFails invalidRedisTls;
assert evaluationFails invalidDragonflyTls;
assert evaluationFails invalidRedisRawCollision;
assert evaluationFails invalidDragonflyRawCollision;
assert evaluationFails invalidDragonflyAclUser;
pkgs.runCommand "nixdb-module-evaluation" { inherit manifestJSON; } ''
  printf '%s' "$manifestJSON" > manifest.json
  ${lib.getExe pkgs.jq} -e '.schemaVersion == 1 and (.instances | length == 5)
    and (.versions.redis == "8.10.0") and (.versions.dragonfly == "1.40.1")
    and ([.instances[].engine] | index("redis") != null)
    and ([.instances[].engine] | index("dragonfly") != null)' manifest.json >/dev/null
  if ${lib.getExe pkgs.gnugrep} -F ${lib.escapeShellArg secret} manifest.json; then
    echo 'runtime manifest leaked the fixture password' >&2
    exit 1
  fi
  touch "$out"
''
