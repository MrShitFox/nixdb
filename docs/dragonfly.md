# Dragonfly

nixdb packages the official immutable Dragonfly v1.40.1 x86_64 Linux release
artifact. It is a Redis-protocol-compatible standalone service; nixdb does not
require Docker and does not orchestrate Dragonfly replication or cluster
topology.

Dragonfly v1.40.1 does not support AOF. nixdb rejects any request to enable
`persistence.aof`; it never maps AOF to snapshots. Local snapshots are the
supported persistence mechanism.

## Store and cache instances

```nix
services.nixdb.dragonfly.instances.store = {
  dataDir = "/srv/databases/dragonfly/store";
  mountPoint = "/";
  projectId = 2501;
  diskLimit = "30G";
  port = 6379;
  maxMemory = "6G";
  proactorThreads = 2;
  cacheMode = false;
  memoryHigh = "7G";
  memoryMax = "8G";
  persistence = {
    # Native Dragonfly snapshots use an extensionless name.
    dbFilename = "dump-{timestamp}";
    snapshotCron = "*/5 * * * *";
  };
};

services.nixdb.dragonfly.instances.cache = {
  dataDir = "/srv/databases/dragonfly/cache";
  mountPoint = "/";
  projectId = 2502;
  diskLimit = "20G";
  port = 6380;
  maxMemory = "2G";
  cacheMode = true;
  memoryHigh = "2500M";
  memoryMax = "3G";
};
```

`maxMemory` is Dragonfly's logical engine limit. `MemoryHigh` starts cgroup
reclaim/pressure and `MemoryMax` is the absolute cgroup ceiling. They are
separate controls; nixdb rejects an engine limit above its hard cgroup limit.
Leave room for allocator and engine overhead. Dragonfly v1.40.1 also requires at
least 256 MiB of `maxMemory` per `proactorThreads`; nixdb validates this before
activation. `proactorThreads` defaults to `1`, deliberately avoiding an
implicit host-CPU-sized thread pool on small memory limits.

## Authentication, TLS, listeners, and tiering

`authentication` accepts the same declarative user shape as Redis and renders
a Dragonfly ACL file plus `requirepass` for the managed admin user. Dragonfly
ACL user names use the same letters/digits/`_`/`-` safe token shape as Redis
(the managed default is `nixdb-admin`). TLS takes
certificate paths only. Optional Memcached and admin/HTTP listeners have their
own ports and firewall booleans; no listener is public by default.

```nix
services.nixdb.dragonfly.instances.edge = {
  dataDir = "/srv/databases/dragonfly/edge";
  mountPoint = "/";
  projectId = 2503;
  diskLimit = "40G";
  port = 6381;
  maxMemory = "4G";
  authentication.password = "CHANGE_ME";
  memcached = { port = 11211; };
  admin = { port = 16379; openFirewall = false; };
  extraFlags = { num_shards = 2; };
};
```

For SSD tiering, set `tiering.enable`, `tiering.prefix`, and `tiering.mountPoint`.
`tiering.mountPoint` must equal the instance `mountPoint`, and `tiering.prefix`
must be beneath `dataDir`. This deliberately keeps tier files inside the same
XFS project quota; v0.3.0 does not pretend that a second, unmodeled path has
the instance's `diskLimit`.

S3 snapshot URL, endpoint, HTTPS, payload-signing, and EC2-metadata flags are
typed under `persistence.s3`. Supply credentials through the environment or
the platform's secret mechanism, never through the sanitized manifest.

## Native flag escape hatch

`extraFlags` maps a current Dragonfly flag name to a boolean, integer, string,
or a list for repeated flags. nixdb rejects a raw flag that collides with a
typed or service-managed field, including data directory, Redis listener,
ACL, daemon behavior, and configured TLS fields. nixdb checks each raw flag
name against the exact pinned binary's `--help`, then passes its value unchanged;
it never silently rewrites an advanced setting.

```nix
services.nixdb.dragonfly.instances.advanced.extraFlags = {
  "num_shards" = 2;
};
```

Native `cluster_mode`, `replicaof`, replication authentication/TLS, and other
supported v1.40.1 flags remain usable. nixdb configures instance processes; it
does not create or fail over a Dragonfly cluster.

`nixdb health` checks the Redis protocol, authentication behavior, effective
memory/cache metadata, a namespaced SET/GET/TTL/DEL probe, optional admin HTTP
and Memcached endpoints, and cleans its test key.
