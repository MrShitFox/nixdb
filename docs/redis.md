# Redis Open Source

nixdb packages Redis Open Source 8.10.0 from the official Redis source release,
with the official RedisBloom, RediSearch, RedisJSON, and RedisTimeSeries
modules built from their release-pinned upstream sources. Vector sets are a
Redis 8 in-tree capability, not a separately loadable module. The package also
contains TLS support, `redis-cli`, `redis-benchmark`, `redis-check-aof`, and
`redis-check-rdb`.

Redis is configured as independent standalone systemd instances. nixdb does
not orchestrate Redis Cluster or Sentinel, but native directives remain
available through `extraConfig`.

## Minimal cache

```nix
services.nixdb.redis.instances.cache = {
  dataDir = "/srv/databases/redis/cache";
  mountPoint = "/";
  projectId = 2401;
  diskLimit = "20G";
  port = 6379;
  maxMemory = "2G";
  maxMemoryPolicy = "allkeys-lru";
  persistence.saveRules = [ ];
  memoryHigh = "2500M";
  memoryMax = "3G";
  cpuWeight = 120;
};
```

The actual option names follow the existing nixdb style: common quota and
resource fields are on the instance, while Redis-specific fields are direct
instance options. `memoryHigh`, `memoryMax`, `memorySwapMax`, and `cpuWeight`
are also accepted directly for consistency with other engines.

## Persistence

Redis can use RDB snapshots, AOF, both, or neither. The default is Redis's
normal snapshot rules with AOF disabled. Set `persistence.saveRules = [ ]` to
disable snapshots explicitly.

```nix
services.nixdb.redis.instances.durable = {
  dataDir = "/srv/databases/redis/durable";
  mountPoint = "/";
  projectId = 2402;
  diskLimit = "40G";
  port = 6380;
  maxMemory = "6G";
  memoryHigh = "7G";
  memoryMax = "8G";
  persistence = {
    appendOnly = true;
    appendFsync = "everysec"; # or "always" or "no"
    aofUseRdbPreamble = true;
  };
};
```

`appendFsync = "always"` asks Redis to synchronously fsync every AOF write;
it can materially increase latency and is not a power-loss guarantee beyond
Redis's documented durability semantics. `everysec` trades up to roughly one
second of acknowledged writes for throughput. `no` leaves fsync scheduling to
the operating system. AOF rewrite and RDB fork overhead mean `maxMemory` must
leave deliberate headroom below `MemoryMax`.

## ACL and TLS

`authentication` renders a Redis ACL file. It supports a disabled default
user, one managed admin user, and named restricted users. Passwords are never
placed in the manifest or CLI JSON.

```nix
services.nixdb.redis.instances.acl = {
  dataDir = "/srv/databases/redis/acl";
  mountPoint = "/";
  projectId = 2403;
  diskLimit = "10G";
  port = 6381;
  authentication = {
    enable = true;
    password = "CHANGE_ME";
    defaultUser.enable = false;
    users.app = {
      password = "CHANGE_ME";
      commands = [ "+@read" "+@write" "-@dangerous" ];
      keys = [ "~app:*" ];
      channels = [ "&app:*" ];
    };
  };
  tls = {
    enable = true;
    port = 6382;
    certFile = "/run/credentials/redis.crt";
    keyFile = "/run/credentials/redis.key";
    caFile = "/run/credentials/ca.crt";
  };
};
```

TLS key material is referenced by path only. Disable the regular TCP port with
`port = null`; Unix-socket-only deployment is supported with `unixSocket` and
`unixSocketPerm`.

## Native configuration escape hatch

`extraConfig` is a structured attrset. A scalar emits one directive and a list
emits it repeatedly. `extraConfigLines` is for directives that cannot be
represented as a key/value pair. nixdb rejects conflicts with typed or
service-owned directives such as `port`, `dir`, `aclfile`, `daemonize`, and
`supervised`; it never silently changes their precedence.

```nix
services.nixdb.redis.instances.advanced.extraConfig = {
  "repl-diskless-sync-delay" = 5;
};
```

Use it for native replication, Sentinel-related, or Cluster directives when
appropriate, but remember that nixdb only manages standalone instance
lifecycle; it does not coordinate topology or failover.

`nixdb health` uses an authenticated Redis protocol probe, verifies owned
memory and persistence settings, runs `MODULE LIST`, tests a namespaced
SET/GET/TTL/DEL key, and cleans that key. It does not use FLUSHDB or FLUSHALL.
